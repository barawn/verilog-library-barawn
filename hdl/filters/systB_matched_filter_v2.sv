`timescale 1ns / 1ps
// systA/B/C are the 4 types of systolic filters.
//
// systB has
// [ 1   0 ]
// [ 1  -1 ] 
// [ 1  -1 ]
// [ 2  -1 ]
// [-2  -4 ]
//
// The way systB works is that it needs 3 DSPs:
// the first computes (A-B), and the second 
// computes (A-B)+(A-B)z^-1 + (A-B)z^-2 in one
// step. A separate ternary adder computes
// (2A - 2Az^-1 -4Bz^-1). The third DSP then
// begins the start of the final cascade, taking
// in the cascade of the second, adding the
// ternary as well as one of the two systA filters.
//
// The systC filter adds its stray plus systA + its output
// via a 3:2 compress into its second DSP slots,
// and then the cascade from systB feeds into the
// next DSP which takes the systC filter's output
// plus the other systA.
// Should work.
`include "dsp_macros.vh"
module systB_matched_filter_v2 #(
        parameter INBITS = 12,
        localparam OUTBITS = INBITS+4        
    )(
        input clk_i,
        input [INBITS-1:0] inA0_i,
        input [INBITS-1:0] inB0_i,
        input [INBITS-1:0] inA1_i,
        input [INBITS-1:0] inB1_i,
        input [47:0] add_i,
        output [47:0] pc_o,
        output [OUTBITS-1:0] out0_o,
        output [OUTBITS-1:0] out1_o
    );

    // The ternary adder here is B(1-z^-1) -2Az^-1.
    localparam TERN_IN_BITS = (INBITS + 1);
    // Ternary add max is 2047 - (-2048) - (-4096) = 8191.
    // Ternary add min is -2048 - 2047 - 4094 = -8189.
    // So we only need 14 total bits.
    localparam TERN_ADD_BITS = TERN_IN_BITS + 1;
    
    wire [1:0][INBITS-1:0] A_input = { inA1_i,
                                       inA0_i };
    wire [1:0][INBITS-1:0] B_input = { inB1_i,
                                       inB0_i };
    
    reg [1:0][INBITS-1:0] A_store = {2*INBITS{1'b0}};
    reg [1:0][INBITS-1:0] B_store = {2*INBITS{1'b0}};

    wire [1:0][TERN_IN_BITS-1:0] in_X;
    wire [1:0][TERN_IN_BITS-1:0] in_Y;
    wire [1:0][TERN_IN_BITS-1:0] in_Z;

    // output of the ternary adder, always 2 more
    wire [1:0][TERN_IN_BITS+1:0] tern_sum;
    wire [1:0][TERN_ADD_BITS-1:0] tern_sum_trunc;
    // systB needs z^-3
    // the DSP structure has at its ALU (with no PREG)
    // (Az^-2 + Bz^-1) = z^-1 timing
    // at the PREG is z^-2
    // the second DSP gives z^-3 timing
    // this means we need z^-6 : the tern sum gives z^-1,
    // so we need 5 more clocks of delays.
    // Therefore we need an srlvec with address = 2 plus
    // the output FF plus the C register.
    wire [1:0][TERN_ADD_BITS-1:0] tern_sum_dly;
    reg [1:0][TERN_ADD_BITS-1:0] tern_sum_store = {2*INBITS{1'b0}};
    
    wire [47:0] dsp0_AB = { {(24-INBITS){A_input[1][INBITS-1]}}, A_input[1],
                            {(24-INBITS){A_input[0][INBITS-1]}}, A_input[0] };
    wire [47:0] dsp0_C  = { {(24-INBITS){B_input[1][INBITS-1]}}, B_input[1],
                            {(24-INBITS){B_input[0][INBITS-1]}}, B_input[0] };
    wire [3:0] dsp0_ALUMODE = `ALUMODE_Z_MINUS_XYCIN;
    wire [8:0] dsp0_OPMODE = { `W_OPMODE_0,
                               `Z_OPMODE_C,
                               `Y_OPMODE_0,
                               `X_OPMODE_AB };
    wire [47:0] dsp0_out;
    wire [47:0] dsp0_cascade;

    wire [47:0] dsp1_AB = dsp0_out;
    wire [47:0] dsp1_C = dsp0_out;
    wire [3:0]  dsp1_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [8:0]  dsp1_OPMODE = { `W_OPMODE_0,
                                `Z_OPMODE_PCIN,
                                `Y_OPMODE_C,
                                `X_OPMODE_AB };
        
    // we don't need dsp1 out anymore.
    wire [47:0] dsp1_cascade;
    
    wire [47:0] dsp2_AB = add_i;
    wire [47:0] dsp2_C = { {(24-TERN_ADD_BITS-1){tern_sum_store[1][TERN_ADD_BITS-1]}}, tern_sum_store[1], 1'b0,
                           {(24-TERN_ADD_BITS-1){tern_sum_store[0][TERN_ADD_BITS-1]}}, tern_sum_store[0], 1'b0 };
    wire [3:0]  dsp2_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [8:0]  dsp2_OPMODE = { `W_OPMODE_0,
                                `Z_OPMODE_PCIN,
                                `Y_OPMODE_C,
                                `X_OPMODE_AB };
    generate
        genvar i;
        for (i=0;i<2;i=i+1) begin : T
           // sign extend
           assign in_X[i] = {B_input[i][INBITS-1], B_input[i]};
           assign in_Y[i] = {B_store[i][INBITS-1], B_store[i]};
           // shift up
           assign in_Z[i] = {A_store[i], 1'b0};
           ternary_add_sub_prim #(.input_word_size(TERN_IN_BITS),
                                  .subtract_y(1'b1),
                                  .subtract_z(1'b1))
                u_tern(.clk_i(clk_i),
                       .rst_i(1'b0),
                       .x_i(in_X[i]),
                       .y_i(in_Y[i]),
                       .z_i(in_Z[i]),
                       .sum_o(tern_sum[i]));
            assign tern_sum_trunc[i] =  tern_sum[i][0 +: TERN_ADD_BITS];
            // Now delay the ternary adder 3 clocks...
            srlvec #(.NBITS(TERN_ADD_BITS))
                u_dly(.clk(clk_i),
                      .ce(1'b1),
                      .a(4'd2),
                      .din(tern_sum_trunc[i]),
                      .dout(tern_sum_dly[i]));
            // and reregister to pick up 4 clocks + the 1 clock of the ternary + 1 clock of C
            // = 6 clocks delay.
            // Plus calculate the storage.
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
              .AREG(2),.BREG(2),
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
                      .PCOUT(dsp1_cascade));    
    wire [47:0] dsp2_out;
    assign out0_o = dsp2_out[0 +: 24];
    assign out1_o = dsp2_out[24 +: 24];                      
    DSP48E2 #(`DE2_UNUSED_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              .USE_SIMD("TWO24"),
              .AREG(1),.BREG(1),
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
                      .PCIN(dsp1_cascade),
                      .P(dsp2_out),
                      .PCOUT(pc_o));    
    
endmodule
