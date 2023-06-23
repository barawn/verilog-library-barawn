`timescale 1ns / 1ps
// testbench for dsp_timed_counter
module dsp_timed_counter_tb;

    wire clk;
    tb_rclk #(.PERIOD(10.0)) u_clk(.clk(clk));
    
    reg count = 0;
    reg [23:0] interval = {24{1'b0}};
    reg load_interval = 0;
    
    wire [23:0] count_out;
    wire count_out_valid;
    
    wire [23:0] ack_count_out;
    wire ack_count_out_valid;
    reg ack_reset = 0;
    
    dsp_timed_counter #(.MODE("NORMAL"))    uut(.clk(clk),
                                                .rst(1'b0), // unused anyway
                                                .count_in(count),
                                                .interval_in(interval),
                                                .interval_load(load_interval),
                                                .count_out(count_out),
                                                .count_out_valid(count_out_valid));

    dsp_timed_counter #(.MODE("ACKNOWLEDGE")) uu2(.clk(clk),
                                                  .rst(ack_reset),
                                                  .count_in(count),
                                                  .interval_in(interval),
                                                  .interval_load(load_interval),
                                                  .count_out(ack_count_out),
                                                  .count_out_valid(ack_count_out_valid));

    
    initial begin
        #100;
        @(posedge clk);
        #1 interval = 50;
        load_interval = 1;
        @(posedge clk);
        #1 load_interval = 0;
        #100;
        @(posedge clk);
        #1 count = 1;
        #100;
        @(posedge clk);
        #1 count = 0;
        while (!ack_count_out_valid) begin
            @(posedge clk); #1;
        end
        @(posedge clk); #1 ack_reset = 1; @(posedge clk); #1 ack_reset = 0;
        
    end
    
endmodule
