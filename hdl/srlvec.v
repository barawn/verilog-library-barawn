// dumb vectorized SRL
// now updated so it doesn't always instantiate SRL32s
// NOTE: if SRL16s are used you only have 4 address bits!
//
// Why would you want to use SRL16s? Because they pack denser:
// you can fit 2 bits in a LUT instead of just one. So generally
// you should always want to use SRL16s.
module srlvec #(parameter NBITS=8,
		parameter USE_SRL16="TRUE",
                localparam ADDR_BITS=(USE_SRL16=="TRUE") ? 4 : 5)
   ( input clk,
     input		   ce,
     input [ADDR_BITS-1:0] a,
     input [NBITS-1:0]	   din,
     output [NBITS-1:0]	   dout);
   generate
      genvar		   i;
      
      for (i=0;i<NBITS;i=i+1) begin : BL
	 if (USE_SRL16 != "TRUE") begin : S32
	    SRLC32E u_bv(.D(din[i]),
			 .CE(ce),
			 .CLK(clk),
			 .A(a),
			 .Q(dout[i]));
	 end else begin : S16
	    SRL16E u_bv(.D(din[i]),
			.CE(ce),
			.CLK(clk),
			.A(a),
			.Q(dout[i]));
	 end
      end // block: BL
   endgenerate
endmodule // srlvec

	 
				    
				   
    
				   
				    
