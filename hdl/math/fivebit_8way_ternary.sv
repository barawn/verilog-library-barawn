`timescale 1ns / 1ps
// 8way add using a tree of ternary adders.
//
// Also optionally adds in a constant into the unused extra.
// I think this is the cheapest possible way to do it.
// It's literally only 4 slices since each ternary adder
// costs you a slice. There are some unused LUTs in the slice
// but the carry chain's used up.
//
// These are all treated as UNSIGNED ADDS so if you're popping
// in signed numbers, you better represent them in offset binary.
// Yes, the ternary addsub prim supports signed adds, but
// that's stupid because it just requires additional fanout of the
// top bit and it suuuuper doesn't matter.
module fivebit_8way_ternary #(parameter [4:0] ADD_CONSTANT = 5'h0)(
        input clk_i,
        input [4:0] A,
        input [4:0] B,
        input [4:0] C,
        input [4:0] D,
        input [4:0] E,
        input [4:0] F,
        input [4:0] G,
        input [4:0] H,
        output [7:0] O
    );
    
    wire [6:0] stage1[2:0];
    wire [4:0] stage1_in[2:0][2:0];

    assign stage1_in[0][0] = A;
    assign stage1_in[0][1] = B;
    assign stage1_in[0][2] = C;

    assign stage1_in[1][0] = D;
    assign stage1_in[1][1] = E;
    assign stage1_in[1][2] = F;
    
    // Stage2 should be optimized. It's not actually a ternary adder
    // so it doesn't actually need to work the way it does.
    assign stage1_in[2][0] = G;
    assign stage1_in[2][1] = H;
    assign stage1_in[2][2] = ADD_CONSTANT;

    generate
        genvar i;
        for (i=0;i<3;i=i+1) begin : S1
            ternary_add_sub_prim #(.input_word_size(5),
                                   .is_signed(1'b0))
                u_stage1(.clk_i(clk_i),
                         .rst_i(1'b0),
                         .x_i(stage1_in[i][0]),
                         .y_i(stage1_in[i][1]),
                         .z_i(stage1_in[i][2]),
                         .sum_o(stage1[i]));     
        end
    endgenerate
    
    // final output. Note that this technically generates
    // a 9 bit output because it thinks it's adding 3 7-bit numbers
    // with full range, but it's not - the total output range is actually
    // only 4 to 252 (-124 to +124).
    
    wire [8:0] stage2_out;
    ternary_add_sub_prim #(.input_word_size(7),
                           .is_signed(1'b0))
                u_stage2(.clk_i(clk_i),
                         .rst_i(1'b0),
                         .x_i(stage1[0]),
                         .y_i(stage1[1]),
                         .z_i(stage1[2]),
                         .sum_o(stage2_out));              
    assign O=stage2_out[7:0];
endmodule
