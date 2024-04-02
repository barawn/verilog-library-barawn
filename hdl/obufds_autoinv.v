`timescale 1ns / 1ps

// utility module to handle connecting an optionally-inverted
// differential output.
// By my convention names always match the schematic,
// which means if it's inverted, we need to connect the Ns
// to the Ps and the Ps to the Ns.
//
// THIS MODULE DOES NOT HANDLE ACTUALLY INVERTING THE INPUT
// YOU HAVE TO DO THAT YOURSELF BECAUSE THERE IS NO OPTIONAL
// INVERTER IN THE PAD
module obufds_autoinv( input I,
		       output O_P,
		       output O_N );

   parameter		      INV = 1'b0;

   wire			      obufds_o;
   wire			      obufds_ob;
   assign O_P = (INV == 1'b1) ? obufds_ob : obufds_o;
   assign O_N = (INV == 1'b1) ? obufds_o : obufds_ob;

   OBUFDS u_obuf(.I(I),.O(obufds_o),.OB(obufds_ob));   
   
endmodule // obufds_autoinv

		       
