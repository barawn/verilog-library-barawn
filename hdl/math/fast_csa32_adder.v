`timescale 1ns / 1ps
// This block implements a 3:2 carry-save preadder
// to feed into DSPs.
// The outputs are the *same width* as the input,
// but the carry out has to be added shifted up one.
//
// NOTE NOTE NOTE: The invert parameter only works with
// 1 selected input at the moment. The logic for this
// will be added later.
module fast_csa32_adder #(parameter NBITS=2,
			  parameter [2:0] INVERT = 3'b000)(
        input CLK,
        input CE,
        input RST,
        input [NBITS-1:0] A,
        input [NBITS-1:0] B,
        input [NBITS-1:0] C,
        output [NBITS-1:0] SUM,
        output [NBITS-1:0] CARRY
    );
    
    // Forcibly generate the damn logic.
    // Use the O6 output for carry, O5 for sum.
    // Sum is:
    // 5 4 3 2 1 0 O5
    // 0 x x 0 0 0 0
    // 0 x x 0 0 1 1
    // 0 x x 0 1 0 1
    // 0 x x 0 1 1 0
    // 0 x x 1 0 0 1
    // 0 x x 1 0 1 0
    // 0 x x 1 1 0 0
    // 0 x x 1 1 1 1 
    // or 96, repeated. So 96969696.
    //
    // If A, B, or C is inverted, we just flop the nybbles.
    //
    // Carry is:
    // 5 4 3 2 1 0 O5
    // 1 x x 0 0 0 0
    // 1 x x 0 0 1 0
    // 1 x x 0 1 0 0
    // 1 x x 0 1 1 1
    // 1 x x 1 0 0 0
    // 1 x x 1 0 1 1
    // 1 x x 1 1 0 1
    // 1 x x 1 1 1 1
    // or E8 repeated. So E8E8E8E8.
    //
    // If A is inverted we have 11010100 = 0xD4
    // If B is inverted we have 10110010 = 0xB2
    // If C is inverted we have 10001110 = 0x8E

    localparam [7:0]	   SUM_LUT = (INVERT == 3'b000) ? 8'h96 : 8'h69;
    localparam [7:0]     CARRY_LUT = INVERT[2] ? 8'h8E :
			              (INVERT[1] ? 8'hB2 :
				       (INVERT[0] ? 8'hD4 : 8'hE8));   
   
    localparam [63:0]	 LUT_INIT = { {4{CARRY_LUT}}, {4{SUM_LUT}} };
   
    wire [NBITS-1:0] sum_to_ff;
    wire [NBITS-1:0] carry_to_ff;
    generate
        genvar i;
        for (i=0;i<NBITS;i=i+1) begin : BL
            LUT6_2 #(.INIT(LUT_INIT)) 
                u_csa_lut(.I5(1'b1),.I4(1'b0),.I3(1'b0),
                          .I2(C[i]),.I1(B[i]),.I0(A[i]),
                          .O5(sum_to_ff[i]),
                          .O6(carry_to_ff[i]));
            FDRE #(.INIT(1'b0)) u_sum_ff(.D(sum_to_ff[i]),.CE(CE),.R(RST),.C(CLK),.Q(SUM[i]));
            FDRE #(.INIT(1'b0)) u_carry_ff(.D(carry_to_ff[i]),.CE(CE),.R(RST),.C(CLK),.Q(CARRY[i]));            
        end
    endgenerate    
endmodule
