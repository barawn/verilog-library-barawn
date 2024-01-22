`timescale 1ns / 1ps
`define DLYFF #0.1
// Reciprocal computation. Try to make as cheap as possible.
// Only works up to NBITS=31 sadly?
module slow_reciprocal #(parameter NBITS=16)(
        input clk_i,
        input calc_i,
        input [NBITS-1:0] in_i,        
        output [NBITS:0] out_o,
        output valid_o
    );
    
    // We're actually computing (2^(NBITS)/input).
    // 
    // need reg [WIDTH-1:0] accum
    // [WIDTH-1:0] divisor
    // [WIDTH-1:0] dividend
    // accum_minus_b = accum-divisor
    // if (!accum_minus_b[WIDTH]) accum <= { accum_minus_b[WIDTH-1:0],dividend[WIDTH-1]}
    // else accum <= {accum[WIDTH:1], dividend[WIDTH-1]}
    // quotient <= {quotient[WIDTH-2:0], !accum_minus_b[WIDTH]}
    //
    // our dividend is fixed (2^(NBITS) so we don't need it
    
    // if we take a look at the 4 bit case and try say 8
    // dividend = 16
    // divisor = 8
    // clk  calc_i   running was_calc remainder     quotient    remainder_minus_divisor
    // 0    1        0       0        X             X           X
    // 1    0        1       1        00000         0000        -8
    // 2    0        1       0        00001         0000        -7
    // 3    0        1       0        00010         0000        -6
    // 4    0        1       0        00100         0000        -4
    // 5    0        1       0        01000         0000        0
    // 6    0        1       0        00000         0001        -8
    // 7    0        1       0        00000         0010        X        
    // (stop at 6)
    // So the overall delay we need is NBITS+2.
    reg running = 0;
    wire dly_valid;
    reg dly_valid_ff = 0;
    
    // We steal an extra delay from remainder[0]. This will allow us to work up to 32 bits.
    SRLC32E valid_dly(.D(remainder[0]),.A(NBITS-1),.Q(dly_valid),.CLK(clk_i),.CE(1'b1));
    
    reg [NBITS:0] remainder = {NBITS+1{1'b0}};
    wire [NBITS:0] remainder_minus_divisor = remainder - { 1'b0, in_i };
    reg [NBITS:0] quotient = {NBITS+1{1'b0}};
    
    always @(posedge clk_i) begin
        // figure out stop in a bit
        if (calc_i) running <= 1'b1;
        else if (dly_valid) running <= 1'b0;
        
        dly_valid_ff <= dly_valid;
        
        // speedup, saves a clock.
        if (calc_i) begin
            remainder <= {{NBITS{1'b0}},1'b1};
            quotient <= {NBITS+1{1'b0}};
        end else if (running) begin
            if (!remainder_minus_divisor[NBITS])
                remainder <= {remainder_minus_divisor[NBITS-1:0], 1'b0 };
            else
                remainder <= {remainder[NBITS-1:0], 1'b0 };
            
            quotient <= {quotient[NBITS-1:0], !remainder_minus_divisor[NBITS]};                
        end
    end
    
    assign out_o = quotient;
    assign valid_o = dly_valid_ff;
    
endmodule
