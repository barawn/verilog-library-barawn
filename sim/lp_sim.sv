`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/04/2025 10:21:29 PM
// Design Name: 
// Module Name: lp_sim
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module lp_sim;

    wire clk;
    tb_rclk #(.PERIOD(2)) u_clk(.clk(clk));
    
    reg [7:0][11:0] adc_indata = {96{1'b0}};
    wire [47:0] tmp_out;

    reg rst = 0;
    wire [7:0][12:0] filt0_out;

    shannon_whitaker_lpfull_v3 #(.INBITS(12))
                               uut(.clk_i(clk),
                                   .rst_i(rst),
                                   .dat_i(adc_indata),
                                   .dat_o(filt0_out));

    initial begin
        #100;
        @(posedge clk);
        #0.1 adc_indata[6] = 16'd1000;
//             adc_indata[4] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[6] = 16'd0;
//             adc_indata[4] = 16'd0;
        #100;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd1000;
//             adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
//             adc_indata[2] = 16'd0;
        #100;
        @(posedge clk);
        #0.1 adc_indata[1] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[1] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[3] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[3] = 16'd0;

        #100;
        @(posedge clk);
        #0.1 adc_indata[4] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[4] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[5] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[5] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[7] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[7] = 16'd0;
    end

endmodule
