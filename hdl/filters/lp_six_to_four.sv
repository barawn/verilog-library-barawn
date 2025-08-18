`timescale 1ns/1ps

module lp_six_to_four #(parameter NBITS=12)(
					    input		 clk_i,
					    input		 ce_i,
					    input [6*NBITS-1:0]	 dat_i,
					    output [4*NBITS-1:0] dat_o);

   reg [4*NBITS-1:0]						 out_buf = {6*NBITS{1'b0}};
   reg [1:0]							 nce_shreg = {2{1'b0}};   
   reg [4*NBITS-1:0]						 dat_store = {2*NBITS{1'b0}};   

   // if ce_i is not high, that means this is the nonvalid phase, and we grab
   // all 4 from the store.
   // ce_i   dat_i        dat_store      out_buf
   // 0      X            DCBA           X
   // 1      JIHGFE       X              DCBA
   // 1      PONMLK       XXJI           HGFE
   // 0      VUTSRQ       PONM           LKJI
   // 1      BAZYXW       X              PONM
   //
   // so if (!ce_i) out_buf <= dat_store;
   //    else if (nce_shreg[0]) out_buf <= dat_i[0 +: 4*NBITS];
   //    else if (nce_shreg[1]) out_buf <= {dat_i[2*NBITS +: 2*NBITS], dat_store[0 +: 2*NBITS] };
   //
   //    if (nce_shreg[0]) dat_store[0 +: 2*NBITS] <= dat_i[4*NBITS +: 2*NBITS];
   //    else if (nce_shreg[1]) dat_store <= dat_i [0 +: 4*NBITS];
   always @(posedge clk_i) begin
      nce_shreg <= { nce_shreg[0], !ce_i };

      if (nce_shreg[0]) out_buf <= dat_i[0 +: 4*NBITS];
      else if (nce_shreg[1]) out_buf <= { dat_i[0 +: 2*NBITS], dat_store[0 +: 2*NBITS] };
      else out_buf <= dat_store;
      
      if (nce_shreg[0]) dat_store[0 +: 2*NBITS] <= dat_i[4*NBITS +: 2*NBITS];
      else if (nce_shreg[1]) dat_store <= dat_i[2*NBITS +: 4*NBITS];
   end

   assign dat_o = out_buf;   
endmodule
			
