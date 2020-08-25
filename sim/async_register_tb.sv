`timescale 1ns/1ps

module async_register_tb;

   wire clkA;
   wire clkB;

   tb_rclk #(.PERIOD(2.6)) u_clkA(.clk(clkA));
   tb_rclk #(.PERIOD(10.0)) u_clkB(.clk(clkB));

   reg [31:0] clkA_counter = {32{1'b0}};
   wire [31:0] clkB_counter;
   
   always @(posedge clkA) clkA_counter <= clkA_counter + 1;

    // an update period of 12 should be fine here
   async_register #(.UPDATE_PERIOD(12)) u_cc_counter(.in_clkA(clkA_counter),
			       .clkA(clkA),
			       .out_clkB(clkB_counter),
			       .clkB(clkB));   
   
endmodule // async_register_tb
