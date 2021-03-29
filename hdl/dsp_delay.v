`timescale 1ns/1ps
`include "dsp_macros.vh"
`define DLYFF #1
module dsp_delay( input fast_clk_i,
                  input fast_rst_i,
                  input count_enable_i,
                  input [15:0] delay_i,
                  output count_reached_o );
    parameter DELAY_SHIFT = 0;
    // PIPELINE_RESET = "NONE" - just feed reset's rising edge detector into DSP with no delay (so reset same clock)
    // PIPELINE_RESET = "SINGLE" - register the rising edge detect (reset *next* clock)
    // PIPELINE_RESET = "DOUBLE" - register the reset, register the rising edge (reset *2nd* clock after)
    parameter PIPELINE_RESET = "DOUBLE";
    // God damnit xilinx
    // Handle this within a generate clause.
    // This is an ISIM bug, not a synthesis/implementation bug.
    // see forums:
    // https://forums.xilinx.com/t5/Simulation-and-Verification/XSIM-Verilog-replication-operator-with-zero-produces-incorrect/td-p/878043
    wire [47:0] delay_dsp_c;
    localparam [47:0] DELAY_DSP_MASK  = { {(32-DELAY_SHIFT){1'b1}}, {(16+DELAY_SHIFT){1'b0}} };
    generate
        if (DELAY_SHIFT == 0) begin : NOSHIFT
            assign delay_dsp_c = { {32{1'b0}}, delay_i };
        end else begin : SHIFT
            assign delay_dsp_c = { {(32-DELAY_SHIFT){1'b0}}, delay_i, {DELAY_SHIFT{1'b0}} };
        end
    endgenerate        
    wire 	delay_dsp_patterndetect;
    wire    load_static_during_reset;
    wire    local_reset;
    reg     reset_rereg = 0;
    always @(posedge fast_clk_i) begin
        reset_rereg <= local_reset;
    end
    generate
        if (PIPELINE_RESET == "NONE") begin : FL
            assign local_reset = fast_rst_i;
            assign load_static_during_reset = (local_reset && !reset_rereg);
        end else begin : PIPE
            (* KEEP = "TRUE" *)
            reg load_static_during_reset_reg = 0;
            always @(posedge fast_clk_i) begin : PR
                load_static_during_reset_reg <= (local_reset && !reset_rereg);
            end
            assign load_static_during_reset = load_static_during_reset_reg;
            if (PIPELINE_RESET == "SINGLE") begin : SP
                assign local_reset = fast_rst_i;
            end else begin : DP
                (* KEEP = "TRUE" *)
                reg local_reset_reg = 0;
                always @(posedge fast_clk_i) begin : DPR
                    local_reset_reg <= fast_rst_i;
                end
                assign local_reset = local_reset_reg;
            end
        end
    endgenerate
        
    // just flag reset the DSPs.
    DSP48E1 #(`A_UNUSED_ATTRS, `B_UNUSED_ATTRS, `D_UNUSED_ATTRS,`NO_MULT_ATTRS,`CONSTANT_MODE_ATTRS,
                .CREG(1'b1),.CARRYINREG(1'b0),
                .SEL_MASK("MASK"),.MASK(DELAY_DSP_MASK),
                .SEL_PATTERN("C"),.USE_PATTERN_DETECT("PATDET"),.AUTORESET_PATDET("RESET_MATCH"))
                delay_dsp(`A_UNUSED_PORTS, `B_UNUSED_PORTS, `D_UNUSED_PORTS,
                            .CLK(fast_clk_i),
                            .OPMODE( {`Z_OPMODE_P, `Y_OPMODE_0, `X_OPMODE_0 } ),
                            .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                            .CARRYINSEL( `CARRYINSEL_CARRYIN ),
                            .INMODE('b0),
                            .CARRYIN(1'b1),
                            .CECARRYIN(1'b0),
                            .RSTALLCARRYIN(1'b0),
                            .C(delay_dsp_c),
                            .CEC(load_static_during_reset),
                            .CEP(count_enable_i),
                            .RSTP(load_static_during_reset),
                            .RSTC(1'b0),
                            .PATTERNDETECT(delay_dsp_patterndetect));

    assign count_reached_o = delay_dsp_patterndetect;

endmodule                  