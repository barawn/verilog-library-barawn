`timescale 1ns / 1ps
`include "dsp_macros.vh"

// This is the zero portion (numerator) of
// a biquad. It's labelled as "single_zero_fir"
// because the *dual* biquad might combine
// the two gains. At least maybe it will. Who knows.

// Note that this ONLY WORKS because bandstops
// have the form a+bz^-1+az^-2.
//
// This module comes AFTER the IIR portion
// b/c it also handles the mux for bypassing everything.
//
// You need to write in a sequence:
// first write:  b (z^-1 coeff)
// second write: a (z^0 / z^-2 coeff)
// then update
//
// The FIR for a biquad are just complementary
// zeros located at the frequency of interest.
// (offset from the unit circle depending on Q factor).
//
// NOTE: This module will work for any number of samples,
// just change NSAMP.
module biquad8_single_zero_fir #(parameter NBITS=16,
				 parameter NFRAC=2,
				 parameter NSAMP=8,
				 parameter OUTBITS=16,
				 parameter OUTFRAC=2,
				 parameter CLKTYPE="ACLK")
   (
    input		       clk,
    input [NBITS*NSAMP-1:0]    dat_i,
    // IGNORE THESE WILL MAKE THIS WORK LATER
    input [NBITS*NSAMP-1:0]    bypass_dat_i,
    input		       bypass_i,
    input [17:0]	       coeff_dat_i,
    input		       coeff_wr_i,
    input		       coeff_update_i,
    output [OUTBITS*NSAMP-1:0] dat_o
    );

   // The normal biquad normally works with
   // coeffs in Q4.14
   // data in  Q17.13
   // intermediate in Q21.27
   // We can't do that because using the D port means
   // we can't do 13 fractional bits, because Q14.13
   // means we could overflow.
   // So for this module we do
   // coeffs in Q4.14
   // data in  Q18.12 and Q15.12
   // trim to  Q14.12 for the preadder
   // intermediate in Q22.26   
   localparam		     AD_FRAC_BITS = 12;
   localparam		     A_BITS = 30;
   localparam		     D_BITS = 27;
   localparam		     P_FRAC_BITS = 26;   
   
   // this takes 2 DSPs
   // we need this sample, last sample, sample before
   // meaning samples 0, 1 need to operate slightly
   // differently
   // so for everyone else, we add in an extra register
   // in the path to pipeline delay.
   //    
   generate
      genvar		     i;
      for (i=0;i<NSAMP;i=i+1) begin : LP
	 wire [NBITS-1:0] this_samp = dat_i[NBITS*i +: NBITS];
	 wire [NBITS-1:0] last_samp = dat_i[NBITS*((i+NSAMP-1)%NSAMP) +: NBITS];
	 wire [NBITS-1:0] llast_samp = dat_i[NBITS*((i+NSAMP-2)%NSAMP) +: NBITS];

	 // dsp1 handles this_samp and llast_samp
	 // we add the preadder reg and possibly mreg
	 // 0 dsp0: AREG=2, DREG=1, MREG=1
	 //         D input = sample[0] = z^0 * z^-8
	 //         A input = sample[6] = z^6 * z^-16
	 //                             = z^-2 * z^-8
	 //         Mult out = b02*(z^0 + z^-2)*z^-16
	 // 0 dsp1: AREG=2, MREG=1
	 //         A input = sample[7] = z^7 * z^-16 = z^-1 * z^-8
	 //         Mult out = (b1*z^-1)*z^-16
	 //         Casc in = b02*(z^0 + z^-2)*z^-16
	 //         P out = ( b02*(z^0 + z^-2) + b1*z^-1)*z^-24
	 //
	 // 1 dsp0: AREG=2, DREG=1, MREG=1
	 //         A input = sample[7], D input = sample[1]
	 //         Casc out = b02*(z^0 + z^-2)*z^-16*z^1
	 // 1 dsp1: AREG=1, MREG=1
	 //         A input = sample[0] = z^0 * z^-8 = z^1(z^-1)*z^-8
	 //         Mult out = b1*z^-1*z^-16*z^1
	 //         P out = z^1*(b02*(z^0 + z^-2) + b1*z^-1)*z^-24
	 //
	 // And then 2-7 are the same, because everything lines up
	 // dsp0: AREG=1, DREG=1, MREG=1
	 // dsp1: AREG=1, MREG=1

	 wire [17:0]	  b_dsp0_to_1;
	 wire [47:0]	  p_dsp0_to_1;

	 wire [47:0]	  fir_out;

	 // note that these automatically store the actual data in ranges that won't overflow
	 localparam A_SIGNEXTEND = ( A_BITS - AD_FRAC_BITS - (NBITS-NFRAC));
	 localparam D_SIGNEXTEND = ( D_BITS - AD_FRAC_BITS - (NBITS-NFRAC));
	 wire [29:0]	  dsp0_A = { {A_SIGNEXTEND{llast_samp[NBITS-1]}}, llast_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
	 wire [26:0]	  dsp0_D = { {D_SIGNEXTEND{this_samp[NBITS-1]}}, this_samp,   {(AD_FRAC_BITS-NFRAC){1'b0}} };	 
	 wire [29:0]	  dsp1_A = { {A_SIGNEXTEND{last_samp[NBITS-1]}}, last_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
	 	 
	 fir_dsp_core #(.USE_C("FALSE"),
			.AREG( i < 2 ? 2 : 1),
			.DREG(1),
			.MULT_REG(1),
			.PREG(0),
			.LOADABLE_B("HEAD"),
			.CLKTYPE(CLKTYPE))
	  u_dsp0( .clk_i(clk),
		  .a_i( dsp0_A ),
		  .d_i( dsp0_D ),
		  .b_i( coeff_dat_i ),
		  .bcout_o( b_dsp0_to_1 ),
		  .load_i( coeff_wr_i ),
		  .update_i( coeff_update_i ),
		  .pcout_o(p_dsp0_to_1));
	 fir_dsp_core #(.ADD_PCIN("TRUE"),
			.USE_C("FALSE"),
			.USE_D("FALSE"),
			.AREG( i < 1 ? 2 : 1 ),
			.MULT_REG(1),
			.PREG(1),
			.LOADABLE_B("TAIL"))
	  u_dsp1( .clk_i(clk),
		  .a_i( dsp1_A ),
		  .bcin_i( b_dsp0_to_1 ),
		  .pcin_i( p_dsp0_to_1 ),
		  .load_i( coeff_wr_i ),
		  .update_i( coeff_update_i ),
		  .p_o(fir_out));	 
	 assign dat_o[OUTBITS*i +: OUTBITS] = fir_out[ (P_FRAC_BITS-OUTFRAC) +: OUTBITS]; 
      end
   endgenerate   

endmodule
 
