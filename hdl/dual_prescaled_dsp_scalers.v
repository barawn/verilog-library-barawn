`timescale 1ns/1ps
`define DLYFF #1
`include "dsp_macros.vh"

// Dual scalers using a single DSP, with variable prescale and overflow detection.
//
// Using a DSP for multiple scalers using SIMD mode isn't easy because none of the control signals
// are duplicated, so you can't use a single flag as an "up" counter and add a fixed amount each time.
//
// But for the case of *2* scalers, you can do a bit of a trick and use the OPMODE inputs as count
// up enables, since the final output is a 3-way add of X+Y+Z. So we assign X (= A) to one of the
// channels and Y (= C) to another of the channels, and switch X from 0->A whenever we want to add
// channel 0, and switch Y from 0->C whenever we want to add channel 1.
//
// Overflow detection is also a bit of a nightmare - we use a second DSP for that (which, OK, seems
// like we're negating the SIMD benefits, but it also acts as a clock-domain cross, storage registers,
// and allows the first DSP to run free), capture the carryout from the first DSP and if those
// carryouts are set, replace the scaler output with FFFFFF.
//
// prescale_en_i is the load-enable for each prescaler.
// fast_rst_i acts to both reset the scaler and load the prescale values.
// fast_rst_done_o is a flag indicating that the load is complete.
// update_i indicates when the accumulation period is done, and value_valid_o
// tells you when the final value is ready after an update.
//
// This module's been implemented at 400 MHz, hence the "fast"
// names and the obsessively huge amount of pipelining.
module dual_prescaled_dsp_scalers( input         fast_clk_i,
                                   input 	 fast_rst_i,
                                   output    fast_rst_done_o,
				   input [1:0]   prescale_en_i,
                                   input [15:0]  prescale_i,
                                   input [1:0] 	 count_i,
                                   input 	 update_i,
                                   output [47:0] value_o,
                                   output 	 value_valid_o );
    parameter PIPELINE_INPUT = "TRUE";
    wire [1:0] local_count_fabric;
    wire [1:0] local_count_dsp;
    
    generate
        if (PIPELINE_INPUT == "TRUE") begin : PIPE                                       
            // Local counts. One for fabric, one for DSP.                                    
            (* KEEP = "TRUE" *)
            reg [1:0] local_count_fabric_ff = {2{1'b0}};
            (* KEEP = "TRUE" *)
            reg [1:0] local_count_dsp_ff = {2{1'b0}};
            always @(posedge fast_clk_i) begin : PIPELOGIC
                local_count_fabric_ff <= count_i;
                local_count_dsp_ff <= count_i;
            end
            assign local_count_fabric = local_count_fabric_ff;
            assign local_count_dsp = local_count_dsp_ff;
        end else begin : DIRECT
            assign local_count_fabric = count_i;
            assign local_count_dsp = count_i;
        end
    endgenerate
    
    wire [47:0] scalA_pcout;
    wire [47:0] scalB_out;
    
    // channel 0 gets the A input.
    // channel 1 gets the C input
    wire [47:0] scalA_ab_in;
    assign scalA_ab_in[24 +: 24] = {24{1'b0}};
    // make this a negative number so that 0 maps to 'count 256' and 255 maps to 'count 1'
    // making this a pure prescale
    assign scalA_ab_in[0 +: 24] = { {16{1'b1}},prescale_i[7:0] };
    // these are all constant, so we can skip the clock enable
    wire [29:0] scalA_a_in = scalA_ab_in[18 +: 30];
    wire [17:0] scalA_b_in = scalA_ab_in[0 +: 18];
    wire [3:0]  scalA_carryout;
    wire [47:0] scalA_c_in;
    assign scalA_c_in[0 +: 24] = {24{1'b0}};
    assign scalA_c_in[24 +: 24] = { {16{1'b1}},prescale_i[15:8] };

    // this is just used as an additional set out of output registers
    // and also to capture the overflow.                      
    
    // Capturing the overflow takes an AMAZING amount of sleaze,
    // and we actually do it in two steps because the ALU's 2 input only
    // Worst case is it happening the clock OF scal_capture
    //
    // scal_capture basically acts as our state machine.
    //
    // clk scal_capture[8:1] carryout X    Z cep carryout_captured  pcout   scalB_out opmode(pre-reg) opmode_next
    // 0   00000001          0        0    p 0   0                  FFFFFF  X         010 00          001 00
    // 1   00000010          0        0    P 0   0                  FFFFFF  X         011 00          010 00
    // 2   00000100          1        0 PCIN 1   0                  0       X         010 00          010 00
    // 3   00001000          0        0    P 1   1                  X       0         010 00          010 {2{carryout_captured}}
    // 4   00010000          0        0    P 1   0                  X       0         010 11          0{2{carryout1_captured}} 10
    // 5   00100000          0        0    P 1   0                  X       0         011 10          010 00
    // 6   01000000          0       AB    P 1   0                  X       0         010 00          010 00
    // 7   10000000          0        P    C 1   0                  X   0000 FFFF     010 00          010 00
    // 8   00000000          0        0    P 0   0                  X   FFFF FFFF     010 00          010 00
    
    // so we do
    // if scal_capture[3] xopmode_next = {2{carryout0_captured[0]}}
    // else xopmode_next = {scal_capture[4],1'b0}
    // 
    // if scal_capture[4] zopmode_next = {2{carryout1_captured[1]}}
    // else zopmode_next = {~scal_capture[0], scal_capture[0]}
    
    // the OPMODE is always X OR Z = 10 1100 (OPMODE[3:2] ALUMODE[3:0])

    // channel 0 gets the AB input
    wire [47:0] scalB_ab_in = { {24{1'b0}}, {24{1'b1}} };
    wire [29:0] scalB_a_in = scalB_ab_in[18 +: 30];
    wire [17:0] scalB_b_in = scalB_ab_in[0 +: 18];
    // channel 1 gets the C input...
    wire [47:0] scalB_c_in = { {24{1'b1}}, {24{1'b0}} };
    
    reg [6:0] opmode = {7{1'b0}};
    reg [1:0] xopmode_next = 2'b00;
    reg [1:0] zopmode_next = 2'b10;

    reg carryout0_captured = 0;
    reg [1:0] carryout1_captured = 2'b00;
                            
    // local capture
    (* KEEP = "TRUE" *)
    reg [8:0] scal_capture = {9{1'b0}};
    (* KEEP = "TRUE" *)
    reg scalB_cep = 0;
    reg scalA_reset = 0;
    reg scal_valid = 0;

    // delayed count flags
    reg [1:0] scal_count_flag_reg = {2{1'b0}};
    // delayed-delayed count flags, to sync with carry
    reg [1:0] scal_count_flag_rereg = {2{1'b0}};
    
    reg reset_rereg = 0;
    reg [1:0] load_static_during_reset = 0;

    reg carry_reset = 0;
    
    reg [1:0] fast_rst_done = 2'b00;
    assign fast_rst_done_o = fast_rst_done[1];
        
    always @(posedge fast_clk_i) begin    
        // Generate a flag to indicate that reset has begun. This loads the static values.
        reset_rereg <= `DLYFF fast_rst_i;
        load_static_during_reset[0] <= `DLYFF (fast_rst_i && !reset_rereg && prescale_en_i[0]);
        load_static_during_reset[1] <= `DLYFF (fast_rst_i && !reset_rereg && prescale_en_i[1]);

        fast_rst_done <= {fast_rst_done[0], fast_rst_i && !reset_rereg};        
       
        // Reset scalA during reset, and also after clock 3 of the scaler capture process
        // (after PCOUT has been captured in scalB
        if (fast_rst_i) scalA_reset <= `DLYFF 1;
        else scalA_reset <= `DLYFF scal_capture[3];

        // scalB's operations start at clock 3 and end at the end (clock 9). So set CE from clock 2 and terminate from clock 8.
        if (scal_capture[2]) scalB_cep <= `DLYFF 1;
        else if (scal_capture[8]) scalB_cep <= `DLYFF 0;

        // Reset the carry capture after fast_rst, and also after clock 3, when it's no longer needed.
        // Note that this process is entirely pipelined, so this puts no restriction on scalA's counting.
        // ScalA's reset is active after clock 3, and our carry reset is also active then.
        if (fast_rst_i) carry_reset <= `DLYFF 1;
        else carry_reset <= `DLYFF scal_capture[3];        

        // This captures the low half-DSP's CARRY output.
        // Note that we have to qualify the carryout by the count flag, because of the way
        // the DSP carry works during subtracts. 
        if (carry_reset) carryout0_captured <= `DLYFF 0;
        else if (scalA_carryout[1] && scal_count_flag_rereg[0]) carryout0_captured <= `DLYFF 1'b1;

        // This captures the high half-DSP's carry output. It's also
        // retained for an extra clock because it's needed a little longer.
        if (carry_reset) carryout1_captured[0] <= `DLYFF 0;
        else if (scalA_carryout[3] && scal_count_flag_rereg[1]) carryout1_captured[0] <= `DLYFF 1'b1;
        // storage for carryout1
        carryout1_captured[1] <= `DLYFF carryout1_captured[0];
        
        // opmode register, just to buy a little extra time.
        opmode <= `DLYFF { 1'b0, zopmode_next, 2'b10, xopmode_next };
        
        // see the table above. This generates the xopmode for scalB's DSP to override the captured value with the carry out for the lower half-DSP
        if (scal_capture[3]) xopmode_next <= `DLYFF {2{carryout0_captured}};
        else xopmode_next <= `DLYFF { scal_capture[4], 1'b0 };
        // see the table above. This generates the yopmode for scalB's DSP to override the captured value with the carry out for the higher half-DSP
        if (scal_capture[4]) zopmode_next <= `DLYFF {2{carryout1_captured[1]}};
        else zopmode_next <= `DLYFF {~scal_capture[0], scal_capture[0] };
        
        // store the count flags so we can qualify the carry
        scal_count_flag_reg <= `DLYFF local_count_fabric;
        scal_count_flag_rereg <= `DLYFF scal_count_flag_reg;
        
        // capture process tracker
        scal_capture <= `DLYFF {scal_capture[7:0],update_i};
        // capture process complete
        scal_valid <= `DLYFF scal_capture[8];    
    end    

    // and now we SLEAZE things horribly by using the OPMODE registers
    // If we count channel 0, OPMODE[1:0] = 11 (X = A:B), otherwise OPMODE[1:0] = 00 (X=0)
    // If we count channel 1, OPMODE[3:2] = 11 (Y = C), otherwise OPMODE[3:2] = 00 (Y=0)
    // Z is always P.
    //
    // ALUMODE is Z-(X+Y+CIN). Since our numbers are negative, we actually count up.
    wire [6:0] scalA_opmode = { `Z_OPMODE_P, {2{local_count_dsp[1]}}, {2{local_count_dsp[0]}} };
    DSP48E1 #(.AREG(1'b0),.ACASCREG(1'b0), `D_UNUSED_ATTRS, `NO_MULT_ATTRS,
              .ALUMODEREG(0),.INMODEREG(0),.OPMODEREG(1),.CARRYINSELREG(0),
              .CREG(1'b1),.CARRYINREG(1'b0),
              .USE_SIMD("TWO24"),.USE_PATTERN_DETECT("NO_PATDET"))
              scalA_dsp(`D_UNUSED_PORTS,
                        .A(scalA_a_in),
                        .CEA2(1'b0),
                        .B(scalA_b_in),
                        .CEB2(load_static_during_reset[0]),
                        .CLK(fast_clk_i),
                        .CECTRL(1'b1),
                        .OPMODE( scalA_opmode ),
                        .ALUMODE( `ALUMODE_Z_MINUS_XYCIN ),
                        .CARRYINSEL( `CARRYINSEL_CARRYIN ),
                        .INMODE('b0),
                        .CARRYIN(1'b0),
                        .CECARRYIN(1'b0),
                        .RSTALLCARRYIN(1'b0),
                        .C(scalA_c_in),
                        .CEC(load_static_during_reset[1]),
                        .CEP(1'b1),
                        .RSTP(scalA_reset),
                        .CARRYOUT(scalA_carryout),
                        .PCOUT(scalA_pcout));

    DSP48E1 #(.AREG(1'b0),.ACASCREG(1'b0),.BCASCREG(1'b0),.BREG(1'b0),.CREG(1'b0), `D_UNUSED_ATTRS,`NO_MULT_ATTRS,.CARRYINREG(1'b0),
              .ALUMODEREG(0),.INMODEREG(1'b0),.CARRYINSELREG(1'b0),.OPMODEREG(1'b1))
                scalB_dsp(`D_UNUSED_PORTS,
                          .A(scalB_a_in),
                          .B(scalB_b_in),
                          .C(scalB_c_in),                          
                            .PCIN(scalA_pcout),
                            .CLK(fast_clk_i),
                            .OPMODE( opmode ),
                            .CECTRL( 1'b1 ),
                            .ALUMODE( 4'b1100 ),
                            .CARRYINSEL( `CARRYINSEL_CARRYIN ),
                            .INMODE(1'b0),
                            .CARRYIN(1'b0),
                            .CECARRYIN(1'b0),
                            .RSTALLCARRYIN(1'b0),
                            .CEP(scalB_cep),
                            .RSTP(1'b0),
                            .P(scalB_out));

    
    assign value_o = scalB_out;
    assign value_valid_o = scal_valid;

endmodule
                                   
