`timescale 1ns / 1ps
// PPS core. Has an internal PPS option plus
// programmable PPS holdoff. Internal PPS comes from int_clk,
// PPS flag output is in ext_clk and the holdoff is in
// 2^16 ext clocks (by default)
// The holdoff and internal PPS use dsp_counter_terminal_count:
// the holdoff in HALT_AT_TCOUNT = TRUE mode, and the internal PPS
// in HALT_AT_TCOUNT = FALSE mode.
// The holdoff only counts when tcount_reached_o is not set,
// which means it needs to be reset (by the next PPS).
module pps_core(
        input int_clk_i,
        input int_sel_i,
        input ext_clk_i,
        input [7:0] ext_holdoff_i,
        input ext_holdoff_wr_i,
        input pps_i,
        output pps_flag_o
    );
    // Number of clocks corresponding to LSB of holdoff.
    parameter HOLDOFF_SHIFT = 16;
    // set USE_DSPS to "FALSE" if you want to disable the DSP holdoffs
    // and just use the logic-defined one.
    parameter USE_DSPS = "TRUE";
    // set USE_INTERNAL_PPS to implement the internal PPS, FALSE if
    // you only want the external PPS to be implemented.
    parameter USE_INTERNAL_PPS = "TRUE";
    // frequency of internal PPS clock
    parameter INTERNAL_FREQ = 1000000;    
    // default holdoff. Just some useful value. 
    parameter DEFAULT_HOLDOFF = 10;
    // use Xilinx ILOGIC hidden registers to resynchronize
    parameter USE_IDDR = "TRUE";
    

    wire [1:0] ext_pps_resync;
    wire ext_pps_holdoff;
    (* ASYNC_REG = "TRUE" *)
    reg [1:0] int_sel_resync = {2{1'b0}};
    wire use_internal_pps_clk = (USE_INTERNAL_PPS == "TRUE") ? int_sel_i : 1'b0;
    wire use_internal_pps = (USE_INTERNAL_PPS == "TRUE") ? int_sel_resync[1] : 1'b0;
    wire internal_pps;
    reg pps_flag = 0;

    // The pps_flag to the outside world.
    always @(posedge ext_clk_i) begin        
        int_sel_resync <= { int_sel_resync[0], int_sel_i };
    
        if (use_internal_pps) pps_flag <= internal_pps;
        else begin
            if (!ext_pps_holdoff) pps_flag <= ext_pps_resync[0] && !ext_pps_resync[0];
            else pps_flag <= 1'b0;
        end
    end
    
    generate
        // PPS resyncing.
        if (USE_IDDR == "TRUE") begin : IDRESYNC
            reg ext_pps_in_reg = 1'b0;
            wire ext_pps_in;
            // Xilinx IDDRs can essentially self-synchronize because
            // they have 2 registers internally. So we use those, plus an additional one
            // for edge detection. You have to do this manually,
            // because the tools aren't smart enough.
            //
            // IDDR:
            // OPPOSITE_EDGE: one FF with input + rising edge clock, one FF with input + falling edge clock
            // SAME_EDGE: one FF with input + rising edge clock
            //            falling edge FF -> rising edge FF
            // SAME_EDGE PIPELINED:
            //            rising edge FF -> rising edge FF
            //            falling edge FF -> rising edge FF
            //
            // Positive edge gives a typical 2-stage synchronizer.
            IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"))
                u_inbuf(.D(pps_i),
                        .CE(1'b1),
                        .C(ext_clk_i),
                        .S(1'b0),
                        .R(1'b0),
                        .Q1(ext_pps_in));
            always @(posedge ext_clk_i) begin : REREG
                ext_pps_in_reg <= ext_pps_in;
            end
            assign ext_pps_resync[0] = ext_pps_in;
            assign ext_pps_resync[1] = ext_pps_in_reg;
        end else begin : LGRESYNC
            (* ASYNC_REG = "TRUE" *)
            reg [2:0] ext_pps_in_reg = {3{1'b0}};
            always @(posedge ext_clk_i) begin : RESYNC
                ext_pps_in_reg <= { ext_pps_in_reg[1:0], pps_i };
            end
            assign ext_pps_resync[0] = ext_pps_in_reg[1];
            assign ext_pps_resync[1] = ext_pps_in_reg[2];
        end

        // ok, so this limits HOLDOFF_SHIFT to 0-40
        wire [47:0] holdoff_count;
        // dumb xilinx bug
        if (HOLDOFF_SHIFT < 40) begin : TP
            assign holdoff_count[HOLDOFF_SHIFT+8 +: (48-HOLDOFF_SHIFT-8)] = {(48-HOLDOFF_SHIFT-8){1'b0}};
        end
        assign holdoff_count[HOLDOFF_SHIFT +: 8] = ext_holdoff_i;
        // dumb xilinx bug
        if (HOLDOFF_SHIFT > 0) begin : SH
            assign holdoff_count[0 +: HOLDOFF_SHIFT] = {HOLDOFF_SHIFT{1'b0}};
        end
        // DSP holdoff
        if (USE_DSPS == "TRUE") begin : HDSP
            reg [2:0] power_on_update = {3{1'b0}};
            always @(posedge ext_clk_i) begin : POUPDATE
                power_on_update <= {power_on_update[1:0],1'b1};
            end
            dsp_counter_terminal_count #(.HALT_AT_TCOUNT("TRUE"),.FIXED_TCOUNT("FALSE"),.RESET_TCOUNT_AT_RESET("FALSE"))
                u_holdoff(.clk_i(ext_clk_i),.rst_i(pps_flag),.count_i(!ext_pps_holdoff),
                          .update_tcount_i(ext_holdoff_wr_i || !power_on_update[2]),
                          .tcount_i( holdoff_count ),
                          .tcount_reached_o(ext_pps_holdoff));
        end else begin : HLGC
            reg [HOLDOFF_SHIFT+8-1:0] holdoff_counter = {(HOLDOFF_SHIFT+8){1'b0}};
            reg [HOLDOFF_SHIFT+8-1:0] holdoff_count_reg = {(HOLDOFF_SHIFT+8){1'b0}};            
            assign ext_pps_holdoff = (holdoff_counter == holdoff_count_reg);
            always @(posedge ext_clk_i) begin : HLDCNT
                if (ext_holdoff_wr_i) holdoff_count_reg <= holdoff_count[0 +: HOLDOFF_SHIFT+8];
                if (pps_flag) holdoff_counter <= {(HOLDOFF_SHIFT+8){1'b0}};
                else begin
                    if (!ext_pps_holdoff) holdoff_counter <= holdoff_counter + 1;
                end
            end
        end
        if (USE_INTERNAL_PPS == "TRUE") begin : INTPPS
            // We allow the internal PPS to be in a different clock domain.
            // If they're in the same one, this just adds a slight delay, no big deal.
            wire internal_pps_clk;
            flag_sync u_intpps_sync(.in_clkA(internal_pps_clk),.clkA(int_clk_i),.out_clkB(internal_pps),.clkB(ext_clk_i));
            if (USE_DSPS == "TRUE") begin : INTPPSDSP
                dsp_counter_terminal_count #(.HALT_AT_TCOUNT("FALSE"),.FIXED_TCOUNT("TRUE"),.FIXED_TCOUNT_VALUE(INTERNAL_FREQ))
                    u_intpps(.clk_i(int_clk_i),.rst_i(!use_internal_pps_clk),.count_i(1'b1),
                             .tcount_reached_o(internal_pps_clk));
            end else begin : INTPPSLOGIC
                // just... make this big. synthesis should trim it.
                reg [47:0] int_counter = {48{1'b0}};
                assign internal_pps = int_counter == INTERNAL_FREQ;
                always @(posedge int_clk_i) begin : INTCNT
                    if (!use_internal_pps) int_counter <= {48{1'b0}};
                    else int_counter <= int_counter + 1;
                end
            end
        end else begin : NOINTPPS
                assign internal_pps = 1'b0;
        end
    endgenerate
    
    
    assign pps_flag_o = pps_flag;
endmodule
