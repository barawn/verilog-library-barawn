`timescale 1ns / 1ps
// Optimized signed 8-bit square.
// See "Combined unsigned and two's complement squarers" with 7-bit combined optimized
// matrix. This module further optimizes things into a ternary adder structure
// with as many of the partial products embedded in the add logic as possible.
//
// The logic here is almost as compact as you can possibly imagine, using 2
// slices of nearly fully utilized logic, including using FFs as logic.
//
// It's *absurdly* smaller than doing
// reg signed [7:0] input_A;
// reg [14:0] output_C;
// always @(posedge clk) output_C <= input_A * input_A;
// which generates about *8 slices* worth of logic.
module signed_8b_square(
        input [7:0] in_i,
        output [15:0] out_o
    );

    // CONSTANT OUTPUTS
    // no square has a power of 2 since 2 is prime
    assign out_o[1] = 1'b0;
    // odd squares are odd, even squares are even
    assign out_o[0] = in_i[0];
   
    // X PARTIALS: These compute ~(a7a1) through ~(a7a6)
    // using DeMorgan's theorem (~(ab) = ~a + ~b)
    wire [6:1]	      X_partial;
    generate
       genvar	      i;
       for (i=1;i<7;i=i+1) begin : XP
	  (* RLOC = "X0Y1", HU_SET = "AUX" *)
	  OR2L #(.IS_SRI_INVERTED(1'b1)) u_xp(.DI(in_i[i] ^ (i==6)),
					      .SRI(in_i[7]),
					      .O(X_partial[i]));	  
       end
    endgenerate

    // COMPRESS INPUTS
   wire b6;
    wire	c7;
   

endmodule
