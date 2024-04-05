`timescale 1ns / 1ps

// utility module to handle connecting an optionally-inverted
// differential input.
// By my convention names always match the schematic,
// which means if it's inverted, we need to connect the Ns
// to the Ps and the Ps to the Ns.
//
// THIS JUST HANDLES CONNECTING UP THE INPUTS, THE OUTPUTS
// ARE STILL INVERTED LOGIC IF INV IS SET
// This is to make it behave the same as the OBUFDS.
// So if it is inverted, pick off the OB output,
// if it is not, pick off the O.

// NOTE NOTE: There are SOME instances where you can't
// just pick off the O or OB, because the component you're
// trying to hook to only connects to either the M or S
// side of the diffpair. This is true for IO clocks and
// ISERDESes as well, because there's a topology you have
// to maintain. This is why the O/OB isn't flipped - the O
// is always the M, OB is always the S. In those cases you
// pick off the one you want and handle the inversion elsewhere.
module ibufds_autoinv( input I_P,
		       input I_N,
		       output O,
		       output OB );

   parameter		      INV = 1'b0;
   wire			      ibufds_i = (INV == 1'b1) ? I_N : I_P;   
   wire			      ibufds_ib = (INV == 1'b1) ? I_P : I_N;
   
   IBUFDS_DIFF_OUT u_ibuf(.I(ibufds_i),.IB(ibufds_ib),.O(O),.OB(OB));
      
endmodule // ibufds_autoinv
