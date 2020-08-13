`timescale 1ns / 1ps

// Testbench clock module. By default, this generates a random phase clock,
// randomized to 10 ps intervals.
// Units of both period and phase are nanoseconds (so it's not really a phase, deal with it).
module tb_rclk( output reg clk );
    parameter PERIOD = 10.0;
    parameter RANDOM_PHASE = "TRUE";
    parameter FIXED_PHASE = 0.0;

    integer phase_10ps;
    integer period_in_10ps;
    real phase;
    real halfperiod;
    initial begin        
        halfperiod = PERIOD/2.0;
        period_in_10ps = PERIOD*100;
        if (RANDOM_PHASE == "TRUE") begin
            phase_10ps = $urandom_range(0, period_in_10ps);
            phase = (phase_10ps)/100.0;
        end else begin
            phase = FIXED_PHASE;
        end
        if (phase > halfperiod) begin
            clk = 1;
            phase = phase - halfperiod;
        end else clk = 0;
        #phase;
        clk = ~clk;
        forever begin
            #halfperiod clk = ~clk;
        end                           
    end 
endmodule