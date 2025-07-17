`timescale 1ns / 1ps
// systA/B/C are the 4 types of systolic filters.
// SystA has two subtypes.
// SystA Subtype 0 is:
// [ 0 0  ]
// [ 1 0  ]
// [ 2 -1 ]
// [ 4 -2 ]
// [-1  4 ]
//
// This gets rearranged to become:
// [ 1  0  ]    [ 0  0 ]
// [ 2  -1 ]    [ 0  0 ]
// [ 0  -2 ]  + [ 4  0 ]
// [ 0  0 ]     [-1  4 ]
//
// Subtype 1 is 
// [ 1 0  ]
// [ 1 -1 ]
// [ 0 -1 ]
// [ 0 -2 ]
// [ 1  1 ]
// rearranged as
// [ 1  0 ]    [ 0  0 ]
// [ 1 -1 ]    [ 0  0 ]
// [ 0 -1 ]  + [ 0  0 ]
// [ 0  0 ]    [ 0 -2 ]
// [ 0  0 ]    [ 1  1 ]
//
// Subtype 0 here can reach a maximum requiring
// 16 bits, and subtype 1 here can reach a maximum
// requiring 15 bits. We therefore make our output
// here 16 bits, although subtype 1 will forcibly
// substitute the top bit as a sign extension.
`include "dsp_macros.vh"
module systA_matched_filter_v2 #(
        parameter SUBTYPE = 0,
        parameter INBITS = 12,
        localparam OUTBITS = INBITS+4        
    )(
        input clk_i,
        input [INBITS-1:0] inA0_i,
        input [INBITS-1:0] inB0_i,
        input [INBITS-1:0] inA1_i,
        input [INBITS-1:0] inB1_i,
        output [47:0] pc_o,
        output [OUTBITS-1:0] out0_o,
        output [OUTBITS-1:0] out1_o
    );

    // Most of the subtype difference is in
    // the ternary adder.
    // Subtype 0 does
    // (4-z^-1)B + 4Az^-1 = 4B - Bz^-1 + 4Az^-1
    // Subtype 1 does
    // (-2+z^-1)A + Bz^-1 = -2A + Bz^-1 + Az^-1
    //
    // To keep the ternary adder identical, we assign
    // x = (4Az^-1 or Az^-1)
    // y = (4B     or Bz^-1)
    // z = ( Bz^-1 or 2A)
    
    // actual number of ternary add bit outputs.
    // subtype 0 goes from -18431 to 18424
    // subtype 1 goes from -8190 to 8190
    // subtype 1 trims off a top bit because it can't actually reach it
    // (it's 1+1+2 not 2+2+2).
    localparam TERN_ADD_BITS = (SUBTYPE == 0) ? 16 : 14;
    // input bits to the ternary adder.
    localparam TERN_IN_BITS = (SUBTYPE == 0) ? 14 : 13;
    wire [1:0][TERN_IN_BITS-1:0] in_X;
    wire [1:0][TERN_IN_BITS-1:0] in_Y;
    wire [1:0][TERN_IN_BITS-1:0] in_Z;
    wire [1:0][TERN_IN_BITS+1:0] tern_sum;
    wire [1:0][TERN_ADD_BITS-1:0] tern_sum_trunc;
    reg [1:0][TERN_ADD_BITS-1:0] tern_sum_store = {2*TERN_ADD_BITS{1'b0}};
    reg [1:0][INBITS-1:0] A_store = {2*INBITS{1'b0}};
    reg [1:0][INBITS-1:0] B_store = {2*INBITS{1'b0}};

    // trace it through:
    // subtype 0:
    // -Bz^-1 (z^-1 z^-1) (z^-1 z^-1) z^-1 = -B z^-6
    // 4B     (z^-1 z^-1) (z^-1 z^-1) z^-1 = 4B z^-5
    // 4Az^-1                              = 4A z^-6
    // DSP
    // (-Az^-2 + Bz^-1)(z^-1)(z^-1) = -Az^-4 + Bz^-3
    // 2(-Az^-2 + Bz^-1)(z^-1)(z^-1)(z^-1) = -2Az^-5 + 2Bz^-4
    //         -Az^-4 -2Az^-5 + 4Az^-6 = correct at z^-2
    // Bz^-3 + 2Bz^-4 + 4Bz^-5 - Bz^-6 = correct at z^-2
    
    wire [1:0][INBITS-1:0] A_input = { inA1_i,
                                       inA0_i };
    wire [1:0][INBITS-1:0] B_input = { inB1_i,
                                       inB0_i };
    wire [47:0] dsp0_out;
    wire [47:0] dsp0_cascade;
    wire [1:0][INBITS:0] dsp0_compute = { dsp0_out[24 +: (INBITS+1)],
                                          dsp0_out[0  +: (INBITS+1)] };
    wire [1:0][23:0] dsp1_C;
    wire [47:0] dsp1_full_C = { dsp1_C[1],
                                dsp1_C[0] };
    wire [47:0] dsp1_cascade;
    wire [47:0] dsp1_out;
    wire [1:0][OUTBITS-1:0] dsp_outputs = { dsp1_out[24 +: OUTBITS],
                                            dsp1_out[0 +: OUTBITS] };
    assign out0_o = dsp_outputs[0];
    assign out1_o = dsp_outputs[1];
    generate
        genvar i;
        for (i=0;i<2;i=i+1) begin : S
            if (SUBTYPE == 0) begin : T0
                // x = 4Az^-1, y = 4B, z = Bz^-1
                assign in_X[i] = { A_store[i], 2'b00 };
                assign in_Y[i] = { B_input[i], 2'b00 };
                assign in_Z[i] = { {2{B_store[i][INBITS-1]}}, B_store[i] };
                // subtype 0 scales the sum up by 2
                assign dsp1_C[i] = { {(24-(INBITS+1)-1){dsp0_compute[i][INBITS]}},
                                     dsp0_compute[i][0 +: (INBITS+1)], 1'b0 };
                                                     
            end else begin : T1
                // x = Az^-1, y = Bz^-1, z = 2A
                assign in_X[i] = { A_store[i][INBITS-1], A_store[i] };
                assign in_Y[i] = { B_store[i][INBITS-1], B_store[i] };
                assign in_Z[i] = { A_input[i], 1'b0 };
                // subtype 1 does not scale up
                assign dsp1_C[i] = { {(24-(INBITS+1)){dsp0_compute[i][INBITS]}},
                                     dsp0_compute[i][0 +: (INBITS+1)] };
            end
            always @(posedge clk_i) begin : ST
                A_store[i] <= A_input[i];
                B_store[i] <= B_input[i];
                tern_sum_store[i] <= tern_sum_trunc[i];
            end
            ternary_add_sub_prim #(.input_word_size(TERN_IN_BITS),
                                   .subtract_z(1'b1))
                u_tern(.clk_i(clk_i),
                       .rst_i(1'b0),
                       .x_i(in_X[i]),
                       .y_i(in_Y[i]),
                       .z_i(in_Z[i]),
                       .sum_o(tern_sum[i]));
            assign tern_sum_trunc[i] =  tern_sum[i][0 +: TERN_ADD_BITS];
        end
    endgenerate

    localparam dsp0_PREG = (SUBTYPE == 0) ? 1 : 0;
    wire [47:0] dsp0_AB = { {(24-INBITS){A_input[1][INBITS-1]}}, A_input[1],
                            {(24-INBITS){A_input[0][INBITS-1]}}, A_input[0] };
    wire [47:0] dsp0_C  = { {(24-INBITS){B_input[1][INBITS-1]}}, B_input[1],
                            {(24-INBITS){B_input[0][INBITS-1]}}, B_input[0] };
    // Z is C, and X is AB
    // We want Z - X so
    wire [3:0] dsp0_ALUMODE = `ALUMODE_Z_MINUS_XYCIN;
    wire [8:0] dsp0_OPMODE = { 2'b00,
                               `Z_OPMODE_C,
                               `Y_OPMODE_0,
                               `X_OPMODE_AB };
    DSP48E2 #(`DE2_UNUSED_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              .USE_SIMD("TWO24"),
              .AREG(2),.BREG(2),
              .CREG(1),
              .PREG(dsp0_PREG))
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
    wire [1:0][23:0] dsp1_AB;
    assign dsp1_AB = { {(24-TERN_ADD_BITS){tern_sum_store[1][TERN_ADD_BITS-1]}}, tern_sum_store[1],
                       {(24-TERN_ADD_BITS){tern_sum_store[0][TERN_ADD_BITS-1]}}, tern_sum_store[0] };
    wire [47:0] dsp1_full_AB = { dsp1_AB[1],
                                 dsp1_AB[0] };
    wire [3:0] dsp1_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [8:0] dsp1_OPMODE = { 2'b00,
                               `Z_OPMODE_PCIN,
                               `Y_OPMODE_C,
                               `X_OPMODE_AB };
    DSP48E2 #(`DE2_UNUSED_ATTRS,
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              .USE_SIMD("TWO24"),
              .AREG(2),.BREG(2),
              .CREG(1),
              .PREG(1))
              u_dsp1( .CLK(clk_i),
                      .A(`DSP_AB_A(dsp1_full_AB)),
                      .B(`DSP_AB_B(dsp1_full_AB)),
                      .C(dsp1_full_C),
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
                      .PCOUT(dsp1_cascade),
                      .P(dsp1_out));
                      
    
endmodule
