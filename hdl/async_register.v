`timescale 1ns/1ps
`define DLYFF #1
// Transfers a multi-bit register across a clock domain.
// This module always works if clkA is running.
// UPDATE_PERIOD specifies how often the update is sent,
// in clkA clocks. If DOUBLE_PERIOD = "TRUE", this period
// is doubled (there's an easy way to do this in the
// clk_div_ce module).
//
// UPDATE_PERIOD should be either 3 (if clkB is faster than clkA)
// or greater than 3x the ratio of clkB to clkA. That is,
// if clkB is 100 MHz and clkA is 200 MHz, UPDATE_PERIOD
// should be at least 6.
//
module async_register #(parameter WIDTH=32, 
			parameter [4:0] UPDATE_PERIOD=31,
			parameter DOUBLE_PERIOD="FALSE")
   (input 	       clkA,
    input [WIDTH-1:0]  in_clkA,
    input 	       clkB,
    output [WIDTH-1:0] out_clkB );
   
   wire 	       update_reg_clkA;
   wire 	       update_reg_clkB;

   reg [WIDTH-1:0]     reg_clkA = {WIDTH{1'b0}};
   // sigh, I wish there was a 'async reg for simulation only'
   // if this tries to pack them it's a waste of time.
   (* ASYNC_REG = "TRUE" *)
   reg [WIDTH-1:0]     pipe_clkB = {WIDTH{1'b0}};
   reg [WIDTH-1:0]     reg_clkB = {WIDTH{1'b0}};

   always @(posedge clkA) if (update_reg_clkA) reg_clkA <= `DLYFF in_clkA;

   always @(posedge clkB) begin
      pipe_clkB <= `DLYFF reg_clkA;
      if (update_reg_clkB) reg_clkB <= `DLYFF pipe_clkB;
   end
   
   flag_sync u_update_flag(.in_clkA(update_reg_clkA),
			   .clkA(clkA),
			   .out_clkB(update_reg_clkB),
			   .clkB(clkB));

   clk_div_ce #(.CLK_DIVIDE(UPDATE_PERIOD),.EXTRA_DIV2(DOUBLE_PERIOD))
   u_clock(.clk(clkA),
	   .ce(update_reg_clkA));
   
	   
   assign out_clkB = reg_clkB;
      
endmodule // async_register
`undef DLYFF