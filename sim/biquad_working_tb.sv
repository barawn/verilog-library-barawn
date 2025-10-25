`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2025 08:07:27 PM
// Design Name: 
// Module Name: biquad_working_tb
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


module biquad_working_tb;

    localparam NSAMP = 4;
    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [NSAMP-1:0][11:0] data = {NSAMP*12{1'b0}};
    
    reg [1:0] coeff_adr = 2'b00;
    reg coeff_wr = 0;
    reg coeff_update = 0;
    reg [17:0] coeff_dat = 18'd0;
    
    task coeff_write;
        input [1:0] adr;
        input [17:0] coeff;
        begin
            @(posedge clk);
            #0.1 coeff_adr <= adr;
                 coeff_dat <= coeff;
                 coeff_wr <= 1;
            @(posedge clk);
            #0.1 coeff_wr <= 0;                 
        end
    endtask
    wire [NSAMP-1:0][11:0] x_out;
    wire [47:0] y0_out;
    wire [47:0] y1_out;        
    biquad8_pole_fir_v2 #(.NSAMP(NSAMP),.NBITS(12))
        uut( .clk(clk),
             .dat_i(data),
             .coeff_adr_i(coeff_adr),
             .coeff_dat_i(coeff_dat),
             .coeff_wr_i(coeff_wr),
             .coeff_update_i(coeff_update),
             .y0_out(y0_out),
             .y1_out(y1_out),
             .x_out(x_out));
    wire [23:0] final_y0;
    wire [23:0] final_y1;
    reg iir_wr = 0;
    biquad8_pole_iir #(.NBITS(24),
                       .NFRAC(10))
        u_iir(.clk(clk),
              .rst(1'b0),
              .coeff_dat_i(coeff_dat),              
              .coeff_wr_i(iir_wr),
              .coeff_update_i(coeff_update),
              .y0_fir_in(y0_out),
              .y1_fir_in(y1_out),
              .y0_out(final_y0),
              .y1_out(final_y1));
    wire [NSAMP-1:0][11:0] final_data;
    reg incr_wr = 0;
    biquad8_incremental_v2 #(.NBITS(12),                             
                             .NFRAC(0),
                             .NBITS2(24),
                             .NFRAC2(10),
                             .NSAMP(NSAMP))
        u_incr(.clk(clk),
               .x_in(x_out),
               .y0_in(final_y0),
               .y1_in(final_y1),
               .coeff_dat_i(coeff_dat),
               .coeff_wr_i(incr_wr),
               .coeff_update_i(coeff_update),
               .dat_o(final_data));    

    // at final_y0/final_y1 we need:
    // (NSAMP+6-smp) clocks to line up with y0/y1.
    // 
              
    // if we suppose we have
    // x[0] = 1     5
    // x[1] = 2     6
    // x[2] = 3     0
    // x[3] = 4     0
    //
    // and we program in C0 = 1, C1 = 2
    //                   D0 = 3, D1 = 4, D2 = 5
    // first actually make sure f/g chains work
    initial begin
        #100;
        coeff_write(0, 18'h1);
        coeff_write(0, 18'h2);
        coeff_write(0, 18'h1);
        coeff_write(1, 18'h1);
        coeff_write(1, 18'h5);
        coeff_write(1, 18'h4);
        coeff_write(1, 18'h3);
        @(posedge clk); 
        #0.1 coeff_update <= 1;
        @(posedge clk);
        #0.1 coeff_update <= 0;
        
        #100;
        @(posedge clk);
        #0.1 data[0] <= 12'd1;
             data[1] <= 12'd2;
             data[2] <= 12'd3;
             data[3] <= 12'd4;
        @(posedge clk);
        #0.1 data[0] <= 12'd5;
             data[1] <= 12'd6;
             data[2] <= 12'd0;
             data[3] <= 12'd0;
        @(posedge clk);
        #0.1 data[0] <= 12'd0;
             data[1] <= 12'd0;
             data[2] <= 12'd0;
             data[3] <= 12'd0;
    end
    
endmodule
