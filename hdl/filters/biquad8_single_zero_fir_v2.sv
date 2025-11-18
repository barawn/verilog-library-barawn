`timescale 1ns / 1ps
`include "dsp_macros.vh"

// (c) Patrick Allison and the Ohio State University (allison.122@osu.edu)
// 11/12/25. Contact for reuse.

// The FIR here rotates samples so instead of
// firred[i] = a*x[i] + b*x[i-1] + a*x[i-2]
// we do
// firred[i] = a*x[i+1] + b*x[i] + a*x[i-1].
// which allows us to bypass the FIR by adjusting
// b to 1.

// We previously went all wacko and tried to cascade everything to save a couple
// of registers, but the 8-DSP chain just makes it too tough with everyone
// having tight timing. So now we just have:
//
// x[0] ->  A(z^-1)
// x[2] ->  D(z^-1)     ->  MREG(z^-1)--+
//                                      |
// x[1] ->  A(z^-1)     ->  MREG(z^-1)--+--- PREG(z^-1)
// for e.g. sample 1.

// For sample 0, dspA's AREG=2, and for sample NSAMP-1,
// dspA is cascaded up and dspB's AREG=2, meaning that it's in the future
// by 1 clock.

//
// Sample NSAMP-1 is adjusted in the future by 1 clock.
//
// The bypass input does 2 things. It forces dspA's MREG into reset and
// swaps the inmode on dspB to multiply by D, which is 1.
//
// For RSTM, the bypassed data shows up after 2 clocks:
// clk  RSTM        MREG    PREG on dspB
// 0    0           M[-2]   P[-3]
// 1    1           M[-1]   P[-2]
// 2    1           0       P[-1]
// 3    1           0       0       <-- bypassed data here
//
// For the INMODE swap, the bypassed data shows up after 3 clocks.
//
// clk  bypass      INMODE  INMODEREG   dspB mult input MREG on dspB    PREG on dspB "bypassed"
// 0    0           5'd0    5'd0        B*A[-1]         B*A[-2]         B*A[-3]         0
// 1    1           5'd6    5'd0        B*A[0]          B*A[-1]         B*A[-2]         0
// 2    1           5'd6    5'd6        A[1]            B*A[0]          B*A[-1]         0
// 3    1           5'd6    5'd6        A[2]            A[1]            B*A[0]          0
// 4    1           5'd6    5'd6        A[3]            A[2]            A[1]            1
//
// Note that our "bypass delay" is therefore 3 clocks - that is, it takes 3 clocks before
// the output data is actually bypassed (or unbypassed).
 
// Here you can see it takes an extra clock for bypass to result in the proper
// PREG output. So what we need to do is use bypass_i to control dspB's inmode,
// and everyone else uses a registered version of it.

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
module biquad8_single_zero_fir_v2 #(parameter NBITS=16,
				 parameter NFRAC=2,
				 parameter NSAMP=8,
				 parameter OUTBITS=16,
				 parameter OUTFRAC=2,
				 parameter CLKTYPE="ACLK")
   (
    input		       clk,
    input [NBITS*NSAMP-1:0]    dat_i,
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
   
   // number of bits to replicate at the top for sign extension
   localparam A_SIGNEXTEND = ( A_BITS - AD_FRAC_BITS - (NBITS-NFRAC));
   localparam D_SIGNEXTEND = ( D_BITS - AD_FRAC_BITS - (NBITS-NFRAC));
   
   // The bypass input forces RSTM on all DSP A's except sample 7 which
   // uses an inmode flip to force the multiplier to zero.
   // 
   // For the V2 fir, we have two DSPs, arranged in a total cascade.
   // sample 0:
   // dspA A input = x[7] AREG=2, MREG=1, PREG=0
   //      D input = x[1] DREG=1
   // dspB A input = x[0] AREG=1, MREG=1, PREG=1, ACASCREG=1
   // sample 1:
   // dspA A input = cascade, AREG=0, MREG=1, PREG=0
   //      D input = x[2] DREG=1
   // dspB A input = x[1] AREG=1, MREG=1, PREG=1
   // this takes 2 DSPs
   // we need this sample, last sample, sample before
   // meaning samples 0, 1 need to operate slightly
   // differently
   // so for everyone else, we add in an extra register
   // in the path to pipeline delay.
   //
   wire [NSAMP-1:0][29:0] acascade;
   wire [NSAMP-1:0][17:0] bcascade;
      
   reg bypass_rereg = 1;
   reg bypass_redelay = 1;
   always @(posedge clk) begin
        bypass_rereg <= bypass_i;
        bypass_redelay <= bypass_rereg;
   end        
   
   `define COMMON_ATTRS .BREG(2),.BCASCREG(1),.ALUMODEREG(0),.OPMODEREG(0),.CARRYINSELREG(0),.USE_PATTERN_DETECT("NO_PATDET")
   generate
      genvar		     i;
      for (i=0;i<NSAMP;i=i+1) begin : LP
        // In the V2 FIR we actually *rotate samples*. This allows
        // easier bypassing since we can swap to the D multiplier set to 1.
        // This means the FIR is actually
        // (bz^1 + a + bz^-1).
        wire [17:0] internal_bcascade;
        wire [47:0] internal_pcascade;
        wire [47:0] fir_out;

        reg [OUTBITS-1:0] fir_rereg = {OUTBITS{1'b0}};

        wire [NBITS-1:0] future_samp = dat_i[NBITS*((i+1)%NSAMP) +: NBITS];
        wire [NBITS-1:0] this_samp = dat_i[NBITS*i +: NBITS];
        wire [NBITS-1:0] last_samp = dat_i[NBITS*((i+NSAMP-1)%NSAMP) +: NBITS];

        // The FIR DSP core doesn't work for all of our trickery,
        // sadly. The last sample (NSAMP-1) has its DSPs flipped (B comes before A)
        // so it needs to be direct.
        localparam dspA_A_INPUT = (i==NSAMP-1) ? "CASCADE" : "DIRECT";
        localparam dspA_B_INPUT = (i == 0) ? "DIRECT" : "CASCADE";

        // the last one picks up an additional register via cascade, because why not
        localparam dspA_AREG = (i == 0) ? 2 : 1;
        localparam dspB_AREG = (i==NSAMP-1) ? 2 : 1;
        wire dspB_CEA1 = (i==NSAMP-1) ? 1'b1 : 1'b0;
        localparam dspA_DREG = 1;
        localparam dspA_ADREG = 0;
        localparam dspA_MREG = 1;
        wire [8:0] dspA_OPMODE = { `W_OPMODE_0, `Z_OPMODE_0, `XY_OPMODE_M };
        wire [8:0] dspB_OPMODE = { `W_OPMODE_0, `Z_OPMODE_PCIN, `XY_OPMODE_M };
        
        wire [3:0] dspA_ALUMODE = `ALUMODE_SUM_ZXYCIN;        
        wire [3:0] dspB_ALUMODE = `ALUMODE_SUM_ZXYCIN;

        // The way our trickery works is that dspB is configured to flip between
        // B2 and D, which is insane that that works. But it does!
        // BMULTSEL = AD
        // AMULTSEL = A
        // PREADDINSEL = B
        wire [4:0] dspB_INMODE = (i==NSAMP-1) ? 
            { 2'b00, bypass_rereg, bypass_rereg, 1'b0 } :
            { 2'b00, bypass_i, bypass_i, 1'b0 };
        wire [4:0] dspA_INMODE = 5'b00100;

        // D is (1<<14). The INMODE control
        // swaps between 1 and coeff1
        wire [26:0] dspB_D = 26'd16384;
        wire [29:0] dspB_A = { {A_SIGNEXTEND{this_samp[NBITS-1]}}, this_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };

        `define COMMON_DSPA_ATTRS   .A_INPUT(dspA_A_INPUT), \
                                    .B_INPUT(dspA_B_INPUT), \
                                    .AREG( dspA_AREG ),     \
                                    .DREG(dspA_DREG),               \
                                    .ADREG(dspA_ADREG),              \
                                    .MREG(dspA_MREG),       \
                                    .AMULTSEL("AD"),        \
                                    .BMULTSEL("B"),         \
                                    .PREADDINSEL("A"),      \
                                    `COMMON_ATTRS

        `define COMMON_DSPB_ATTRS   .B_INPUT("CASCADE"),    \
                                    .A_INPUT("DIRECT"),     \
                                    .AREG(dspB_AREG),       \
                                    .DREG(0),               \
                                    .ADREG(0),              \
                                    .MREG(1),               \
                                    .BMULTSEL("AD"),        \
                                    .PREADDINSEL("B"),      \
                                    .AMULTSEL("A"),         \
                                    .INMODEREG(1),          \
                                    `COMMON_ATTRS
                                            
        if (i == 0) begin : AHEAD
            wire [29:0] dspA_A = { {A_SIGNEXTEND{last_samp[NBITS-1]}}, last_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
            wire [26:0] dspA_D = { {D_SIGNEXTEND{future_samp[NBITS-1]}}, future_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
            (* CUSTOM_CC_DST = CLKTYPE *)
            DSP48E2 #( `COMMON_DSPA_ATTRS,
                       .INMODEREG(0),
                       .PREG(0) )
                u_dspA( .A(dspA_A),
                        .B( coeff_dat_i ),
                        `C_UNUSED_PORTS,
                        .D(dspA_D),
                        .OPMODE( dspA_OPMODE ),
                        .ALUMODE( dspA_ALUMODE ),
                        .CARRYIN(1'b0),
                        .CARRYINSEL(3'b000),
                        .INMODE( dspA_INMODE ),
                        .CEA1(  1'b1    ),
                        .CEA2(  1'b1    ),
                        .CEB1( coeff_wr_i ),
                        .CEB2( coeff_update_i ),
                        .CED( 1'b1 ),
                        .CEM( 1'b1 ),
                        .RSTA(1'b0),
                        .RSTB(1'b0),
                        .RSTD(1'b0),
                        .RSTM(bypass_rereg),
                        .RSTCTRL(1'b0),
                        .RSTALLCARRYIN(1'b0),
                        .RSTALUMODE(1'b0),
                        .RSTINMODE(1'b0),
                        .CLK(clk),
                        .BCOUT(internal_bcascade),
                        .PCOUT(internal_pcascade));                                        
        end else        
        if (i < (NSAMP-1)) begin : ABODY
            // for most of the chain it gets the A input from the prior dspB
            wire [29:0] dspA_A = { {A_SIGNEXTEND{last_samp[NBITS-1]}}, last_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
            wire [26:0] dspA_D = { {D_SIGNEXTEND{future_samp[NBITS-1]}}, future_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
            DSP48E2 #( `COMMON_DSPA_ATTRS,
                       .ACASCREG(1),
                       .INMODEREG(0),
                       .PREG(0) )
                u_dspA( .A(dspA_A),
                        .BCIN(bcascade[i-1]),
                        `C_UNUSED_PORTS,
                        .D(dspA_D),
                        .OPMODE( dspA_OPMODE ),
                        .ALUMODE( dspA_ALUMODE ),
                        .CARRYIN(1'b0),
                        .CARRYINSEL(3'b000),
                        .INMODE( dspA_INMODE ),
                        .CEA2(1'b1),
                        .CEB1( coeff_wr_i ),
                        .CEB2( coeff_update_i ),
                        .CED( 1'b1 ),
                        .CEM( 1'b1 ),
                        .RSTA(1'b0),
                        .RSTB(1'b0),
                        .RSTD(1'b0),
                        .RSTM(bypass_rereg),
                        .RSTCTRL(1'b0),
                        .RSTALLCARRYIN(1'b0),
                        .RSTALUMODE(1'b0),
                        .RSTINMODE(1'b0),
                        .CLK(clk),
                        .BCOUT(internal_bcascade),
                        .PCOUT(internal_pcascade));
            end else begin : ATAIL
                wire [26:0] dspA_D = { {D_SIGNEXTEND{future_samp[NBITS-1]}}, future_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
                // IS_INMODE_INVERTED = 5'b00100
                DSP48E2 #( `COMMON_DSPA_ATTRS,
                           .ACASCREG(1),
                           .INMODEREG(0),
                           .PREG(0) )
                    u_dspA( .ACIN(acascade[i-1]),
                            .BCIN(bcascade[i-1]),
                            `C_UNUSED_PORTS,
                            .D(dspA_D),
                            .OPMODE( dspA_OPMODE ),
                            .ALUMODE( dspA_ALUMODE ),
                            .CARRYIN(1'b0),
                            .CARRYINSEL(3'b000),
                            .INMODE( dspA_INMODE ),
                            .CEA2(  1'b1    ),
                            .CED(   1'b1    ),
                            .CEB1( coeff_wr_i ),
                            .CEB2( coeff_update_i ),
                            .CEM(1'b1),
                            .CEAD(1'b0),
                            .CEP( 1'b0 ),
                            .RSTA(1'b0),
                            .RSTB(1'b0),
                            .RSTM(bypass_redelay),
                            // just reset the preadd register in bypass
                            .RSTD(1'b0),
                            .RSTCTRL(1'b0),
                            .RSTALLCARRYIN(1'b0),
                            .RSTALUMODE(1'b0),
                            .RSTINMODE(1'b0),
                            .CLK(clk),
                            .BCOUT(internal_bcascade),
                            .PCOUT(internal_pcascade));
            end

            DSP48E2 #( `COMMON_DSPB_ATTRS,
                        .PREG(1))
                u_dspB( .A(dspB_A),
                        .BCIN(internal_bcascade),
                        `C_UNUSED_PORTS,
                        .D(dspB_D),
                        .OPMODE( dspB_OPMODE ),
                        .ALUMODE( dspB_ALUMODE ),
                        .CARRYIN(1'b0),
                        .CARRYINSEL(3'b000),
                        .INMODE( dspB_INMODE ),
                        .CEB1( coeff_wr_i ),
                        .CEB2( coeff_update_i ),
                        .CEA1( dspB_CEA1 ),
                        .CEA2( 1'b1 ),
                        .CEM( 1'b1 ),
                        .CEP( 1'b1 ),
                        .CEINMODE( 1'b1 ),
                        .RSTA(1'b0),
                        .RSTB(1'b0),
                        .RSTD(1'b0),
                        .RSTM(1'b0),
                        .RSTCTRL(1'b0),
                        .RSTALLCARRYIN(1'b0),
                        .RSTALUMODE(1'b0),
                        .RSTINMODE(1'b0),
                        .CLK(clk),
                        .BCOUT( bcascade[i] ),
                        .ACOUT( acascade[i] ),
                        .PCIN( internal_pcascade ),
                        .P(fir_out));                            

            always @(posedge clk) begin : RR
                fir_rereg <= fir_out[ (P_FRAC_BITS-OUTFRAC) +: OUTBITS];
            end
    	    assign dat_o[OUTBITS*i +: OUTBITS] =  (i==NSAMP-1) ? fir_out[ (P_FRAC_BITS-OUTFRAC) +: OUTBITS] : fir_rereg;
        end
    endgenerate                                          
endmodule
 
