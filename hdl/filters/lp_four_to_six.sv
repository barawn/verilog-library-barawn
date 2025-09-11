`timescale 1ns/1ps

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

module lp_four_to_six #(parameter NBITS=12)(
					    input		 clk_i,
					    input		 clk_phase_i,
					    input [4*NBITS-1:0]	 dat_i,
					    output [6*NBITS-1:0] dat_o,
					    output		 ce_o );

   reg [6*NBITS-1:0]						 out_buf = {6*NBITS{1'b0}};
   reg [2:0]							 clk_phase_buf = {3{1'b0}};
   reg [2*NBITS-1:0]						 dat_store = {2*NBITS{1'b0}};   
   reg								 outbuf_valid = 0;
   
   always @(posedge clk_i) begin
      if (clk_phase_i) clk_phase_buf <= 3'b010;
      else clk_phase_buf <= { clk_phase_buf[1:0], clk_phase_buf[2] };

      if (clk_phase_buf[0]) 
	out_buf[0 +: 4*NBITS] <= dat_i[0 +: 4*NBITS];
      else if (clk_phase_buf[2])
	out_buf[0 +: 4*NBITS] <= { dat_i[0 +: 2*NBITS], dat_store };

      if (clk_phase_buf[1])
	out_buf[4*NBITS +: 2*NBITS] <= dat_i[0 +: 2*NBITS];
      else if (clk_phase_buf[2])
	out_buf[4*NBITS +: 2*NBITS] <= dat_i[2*NBITS +: 2*NBITS];

      if (clk_phase_buf[1])
	dat_store <= dat_i[NBITS*2 +: NBITS*2];
      
      outbuf_valid <= (clk_phase_buf[1] || clk_phase_buf[2]);
      
   end
   
   assign dat_o = out_buf;
   assign ce_o = outbuf_valid;
   
endmodule
			
