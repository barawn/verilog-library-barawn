`timescale 1ns / 1ps
// systA/B/C are the 4 types of systolic filters,
//
// systC has
// [ -1  -1 ]
// [ -1   0 ] 
// [  0   1 ]
// [  0   1 ]
// [ -4   0 ]
// [  1   1 ]
//
// systC uses 3 DSPs, but the third one completes
// the matched filter, cascading from systB.
// The first DSP takes both A_store and B, and
// delays A_store by an extra using the A register,
// generating (-Bz^-1 + Az^-3)z^-1, or z^-2 timing.
// We take that output and feed it into the C register
// and add in cascade to generate
// (-B + Az^-2)z^-2(1+z^-1) at the ALU input.
// We subtract A from the systA systolic
// output, generating Az^-1, and when registered, we get
// (-B-Bz^-1+Az^-2+Az^-3-A)z^-2 + systA z^-2
// Note that our inputs are going to have to be delayed to
// align, but that's fine.
//
// When registered, the systC portion of the filter has
// (-B-Bz^-1+Az^-2+Az^-3-A)z^-3 + systA z^-3
// Our ternary add is -4Bz^-4 + Bz^-5 +Az^-5. We
// grab A_store and B_store and add with a shifted version of B,
// generating (Bz^-1 + Az^-1 - 4B)z^-1 when registered.
// We need z^-3 extra, and then z^-3 extra again to align
// with the P output from the prior fed into the C input.
// So that's an SRL with address 4 (z^-5) plus its FF (z^-6).
//
// our output here is now the full matched filter.
// This means we need to add the rounding constant.
`include "dsp_macros.vh"
module systC_matched_filter_v2 #(
        parameter INBITS = 12,
        parameter [47:0] RND = {48{1'b0}},
        parameter USE_RND = "FALSE",
        parameter OUTBITS = INBITS+4        
    )(
        input clk_i,
        input [INBITS-1:0] inA0_i,
        input [INBITS-1:0] inB0_i,
        input [INBITS-1:0] inA1_i,
        input [INBITS-1:0] inB1_i,
        input [47:0] add_i,
        input [47:0] pc_i,
        output [1:0] saturation_o,
        output [OUTBITS-1:0] out0_o,
        output [OUTBITS-1:0] out1_o
    );

    // The ternary adder here is (Bz^-1 + Az^-1 - 4B). Expand by 2 bits.
    localparam TERN_IN_BITS = (INBITS + 2);
    // Ternary adder range is -12284 to 12286, so it just needs 1 bit of growth.
    localparam TERN_ADD_BITS = TERN_IN_BITS + 1;
    
    wire [1:0][INBITS-1:0] A_input = { inA1_i,
                                       inA0_i };
    wire [1:0][INBITS-1:0] B_input = { inB1_i,
                                       inB0_i };
    
    reg [1:0][INBITS-1:0] A_store = {2*INBITS{1'b0}};
    reg [1:0][INBITS-1:0] B_store = {2*INBITS{1'b0}};
    
    // add_combine is the ternary adder plus the stray bit
    reg [1:0][TERN_ADD_BITS-1:0] add_combine = {2*TERN_ADD_BITS{1'b0}};
    

    wire [1:0][TERN_IN_BITS-1:0] in_X;
    wire [1:0][TERN_IN_BITS-1:0] in_Y;
    wire [1:0][TERN_IN_BITS-1:0] in_Z;

    // output of the ternary adder, always 2 more
    wire [1:0][TERN_IN_BITS+1:0] tern_sum;
    wire [1:0][TERN_ADD_BITS-1:0] tern_sum_trunc;

    // The ternary adder output is (Bz^-1 + Az^-1 - 4B)z^-1
    // We need z^-6 so that's an srlvec with address 4 (z^-5) plus its FF.
    // 
    wire [1:0][TERN_ADD_BITS-1:0] tern_sum_dly;
    reg [1:0][TERN_ADD_BITS-1:0] tern_sum_store = {2*TERN_ADD_BITS{1'b0}};

    // Combining with the ternary is easy since it's already
    // heavily delayed. So undelaying is fine. 
    always @(posedge clk_i) begin
        add_combine[0] <= tern_sum_store[0] - { {4{inA0_i[INBITS-1]}}, inA0_i };
        add_combine[1] <= tern_sum_store[1] - { {4{inA1_i[INBITS-1]}}, inA1_i };
    end
    
    wire [47:0] dsp0_AB = { {(24-INBITS){A_store[1][INBITS-1]}}, A_store[1],
                            {(24-INBITS){A_store[0][INBITS-1]}}, A_store[0] };
    wire [47:0] dsp0_C  = { {(24-INBITS){B_input[1][INBITS-1]}}, B_input[1],
                            {(24-INBITS){B_input[0][INBITS-1]}}, B_input[0] };
    // We need A_store in AB to get the extra register,
    // but then we have to do sleaze.
    // ALUMODE_XYCIN_MINUS_Z_MINUS_1 is actually 'invert C and add AB'.
    // In our SIMD mode, we need to add 24'h1,24'h1                            
    wire [3:0] dsp0_ALUMODE = `ALUMODE_XYCIN_MINUS_Z_MINUS_1;
    localparam [47:0] dsp0_RND = { 24'h1, 24'h1 };
    wire [8:0] dsp0_OPMODE = { `W_OPMODE_RND,
                               `Z_OPMODE_C,
                               `Y_OPMODE_0,
                               `X_OPMODE_AB };
    wire [47:0] dsp0_out;
    wire [47:0] dsp0_cascade;

    wire [47:0] dsp1_AB = { {24-TERN_ADD_BITS{add_combine[1][TERN_ADD_BITS-1]}}, add_combine[1],
                            {24-TERN_ADD_BITS{add_combine[0][TERN_ADD_BITS-1]}}, add_combine[0] };
    wire [47:0] dsp1_C = dsp0_out;
    wire [3:0]  dsp1_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [8:0]  dsp1_OPMODE = { `W_OPMODE_0,
                                `Z_OPMODE_PCIN,
                                `Y_OPMODE_C,
                                `X_OPMODE_AB };
        
    // dsp1 doesn't cascade in systC.
    wire [47:0] dsp1_out;
    
    wire [47:0] dsp2_AB = add_i;
    wire [47:0] dsp2_C = dsp1_out;
    
    wire [3:0]  dsp2_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [8:0]  dsp2_OPMODE = { (USE_RND == "TRUE") ? `W_OPMODE_RND : `W_OPMODE_0,
                                `Z_OPMODE_PCIN,
                                `Y_OPMODE_C,
                                `X_OPMODE_AB };
    generate
        genvar i;
        for (i=0;i<2;i=i+1) begin : T
           // The ternary input is then (Bz^-1 + Az^-1 - 4B)
           // So inX = B_store expanded by 2 bits
           //    inY = A_store expanded by 2 bits
           //    inZ = B upshifted by 2 bits and subtract Z
           // sign extend
           assign in_X[i] = {{2{B_store[i][INBITS-1]}}, B_store[i]};
           assign in_Y[i] = {{2{A_store[i][INBITS-1]}}, A_store[i]};
           // shift up 2
           assign in_Z[i] = {B_input[i], 2'b00};
           ternary_add_sub_prim #(.input_word_size(TERN_IN_BITS),
                                  .subtract_z(1'b1))
                u_tern(.clk_i(clk_i),
                       .rst_i(1'b0),
                       .x_i(in_X[i]),
                       .y_i(in_Y[i]),
                       .z_i(in_Z[i]),
                       .sum_o(tern_sum[i]));
            assign tern_sum_trunc[i] =  tern_sum[i][0 +: TERN_ADD_BITS];
            // Now delay the ternary adder 4 clocks...
            srlvec #(.NBITS(TERN_ADD_BITS))
                u_dly(.clk(clk_i),
                      .ce(1'b1),
                      .a(4'd1),
                      .din(tern_sum_trunc[i]),
                      .dout(tern_sum_dly[i]));
            // and reregister to pick up 5 clocks + the 1 clock of the ternary + 1 clock of C
            // = 7 clocks delay.
            // and generate the store
            always @(posedge clk_i) begin : TD
                A_store[i] <= A_input[i];
                B_store[i] <= B_input[i];
                tern_sum_store[i] <= tern_sum_dly[i];
            end
        end
    endgenerate

    DSP48E2 #(`DE2_UNUSED_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              .USE_SIMD("TWO24"),
              .AREG(2),.BREG(2),
              .RND(dsp0_RND),
              .CREG(1),
              .PREG(1))
              u_dsp0( .CLK(clk_i),
                      .A(`DSP_AB_A(dsp0_AB)),
                      .B(`DSP_AB_B(dsp0_AB)),
                      .C(dsp0_C),
                      .CEA2(1'b1),
                      .CEA1(1'b1),
                      .CEB2(1'b1),
                      .CEB1(1'b1),
                      .CEC(1'b1),
                      .CEP(1'b1),
                      .CARRYINSEL(`CARRYINSEL_CARRYIN),
                      .CARRYIN(1'b0),
                      .ALUMODE(dsp0_ALUMODE),
                      .OPMODE(dsp0_OPMODE),
                      .PCOUT(dsp0_cascade),
                      .P(dsp0_out));
    DSP48E2 #(`DE2_UNUSED_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              .USE_SIMD("TWO24"),
              .AREG(1),.BREG(1),
              .CREG(1),
              .PREG(1))
              u_dsp1( .CLK(clk_i),
                      .A(`DSP_AB_A(dsp1_AB)),
                      .B(`DSP_AB_B(dsp1_AB)),
                      .C(dsp1_C),
                      .CEA2(1'b1),
                      .CEA1(1'b1),
                      .CEB2(1'b1),
                      .CEB1(1'b1),
                      .CEC(1'b1),
                      .CEP(1'b1),
                      .CARRYINSEL(`CARRYINSEL_CARRYIN),
                      .CARRYIN(1'b0),
                      .ALUMODE(dsp1_ALUMODE),
                      .OPMODE(dsp1_OPMODE),
                      .PCIN(dsp0_cascade),
                      .P(dsp1_out));    
    wire [47:0] dsp2_out;
    assign out0_o = dsp2_out[0 +: 24];
    assign out1_o = dsp2_out[24 +: 24];                      

    DSP48E2 #(`DE2_UNUSED_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              .USE_SIMD("TWO24"),
              .RND(RND),
              .AREG(2),.BREG(2),
              .CREG(1),
              .PREG(1))
              u_dsp2( .CLK(clk_i),
                      .A(`DSP_AB_A(dsp2_AB)),
                      .B(`DSP_AB_B(dsp2_AB)),
                      .C(dsp2_C),
                      .CEA2(1'b1),
                      .CEA1(1'b1),
                      .CEB2(1'b1),
                      .CEB1(1'b1),
                      .CEC(1'b1),
                      .CEP(1'b1),
                      .CARRYINSEL(`CARRYINSEL_CARRYIN),
                      .CARRYIN(1'b0),
                      .ALUMODE(dsp2_ALUMODE),
                      .OPMODE(dsp2_OPMODE),
                      .PCIN(pc_i),
                      .P(dsp2_out),
                      .PCOUT(pc_o));    
    
endmodule
