// dumb vectorized SRL
module srlvec #(parameter NBITS=8)( input clk,
				    input 	       ce,
				    input [5:0]        a,
				    input [NBITS-1:0]  din,
				    output [NBITS-1:0] dout);
   generate
      genvar 					       i;

      for (i=0;i<NBITS;i=i+1) begin : BL
	 SRLC32E u_bv(.D(din[i]),
		      .CE(ce),
		      .CLK(clk),
		      .A(a),
		      .Q(dout[i]));
      end
   endgenerate
endmodule // srlvec

	 
				    
				   
    
				   
				    
