`timescale 1ns / 1ps
// Floor-shift approximation to log2. This is for a 20-bit number,
// I'll find a way to approximate this later.
//
// The floor shift approximation to log2 just does:
// 1) Count to the highest bit set (start from 0). That's the integer value.
//    That is, if bit 5 is set, the integer value is 5.
//    Call that "intlog" so intlog(54) is 5 since bit 5 is highest set.
// 2) The fractional part is (input - 2^intlog)/2^intlog.
// 
// In practice this is amazingly stupid: you progressively downshift into
// a new register until the original register is all zero, incrementing
// each time.
//
// NOTE: floorshift_log2(0) is 0. This is just a dumb feature.
// The computation takes a variable amount of time but a timer
// outputs a valid based on the max time.
//
// If you're wondering how this works: it's a piecewise-linear approximation
// to the log between powers of 2. Basically this is exact at each power
// of 2 (floorshift_log2(8) = 3, floorshift_log2(16)=4)
// and then *between* those powers of 2 (from 8 to 16) it's just linear:
// 9  = 11.001 = 3.125
// 10 = 11.010 = 3.25
// 11 = 11.011 = 3.375
// ..
// 14 = 11.110 = 3.75
// 15 = 11.111 = 3.875
// 16 = 100.000 = 4
// 
// The output is convergently rounded to the number of fractional bits
// requested.
module floorshift_log2 #(parameter FRAC_BITS=8)(
        input clk_i,
        input [19:0] in_i,
        input calc_i,
        output [FRAC_BITS+5-1:0] out_o,
        output valid_o
    );

    // calculation delay. We add an extra clock to correct the count register
    SRLC32E u_delay(.D(calc_i),.A(5'd19),.CE(1'b1),.CLK(clk_i),
                    .Q(srl_valid));
    reg valid = 0;                    
    reg [19:0] integer_reg = {20{1'b0}};
    wire stop = (integer_reg == {20{1'b0}});
    reg [4:0] count_reg = {5{1'b0}};
    // The extra bits here are due to the stop delay and convergent rounding.
    reg [FRAC_BITS+1:0] frac_reg = {FRAC_BITS+2{1'b0}};
    reg running = 0;
    reg was_calc = 0;

    always @(posedge clk_i) begin
        if (calc_i) running <= 1;
        else if (stop) running <= 0;
        
        // delay the reset of the count register by 1.        
        was_calc <= calc_i;
                    
        if (calc_i) integer_reg <= in_i;
        else integer_reg <= {1'b0,integer_reg[19:1]};
                
        if (was_calc) count_reg <= {5{1'b0}};
        else if (running && !stop) count_reg <= count_reg + 1;

        if (running && !stop) begin
            frac_reg <= { integer_reg[0], frac_reg[FRAC_BITS+1:1] };        
        end
        valid <= srl_valid;
    end

    // convergent round on the bottom bit
    assign out_o = {count_reg, frac_reg[2 +: (FRAC_BITS-1)],
                    |frac_reg[1:0]
                   };
    // change this to give fixed latency
    assign valid_o = valid;
endmodule
