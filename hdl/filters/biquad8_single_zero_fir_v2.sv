`timescale 1ns / 1ps
`include "dsp_macros.vh"

// WE DON'T ACTUALLY NEED TO BYPASS! WE CAN EMBED
// A "NO-FIR" INTO THE FIR.
//
// WE ARE ACCOMPLISHING MASSIVE SLEAZE HERE.
// Here's the key: the FIR portion of the notch
// is independent of the IIR. So what we can actually
// do is ADJUST THE TIME SEQUENCE of the FIR when
// it's running. Because the ENTIRE SURF gets
// notched or no-notched, this doesn't cause a problem.
//
// In other words, instead of doing:
// firred[i] = a*x[i] + b*x[i-1] + a*x[i-2]
// we do
// firred[i] = a*x[i+1] + b*x[i] + a*x[i-1].
//
// Obviously in this case we have to adjust things
// for sample NSAMP-1 and 0
//
// e.g. for sample 1 we have
// x[0]     ->      A(z^-1)
// x[2]     ->      D(z^-1)     --> MREG(z^-1)--+
//                                              |
// x[1]     ->      A(z^-1)     --> MREG(z^-1> -+---- PREG(z^-1)
// giving a total delay of z^-3
//
// sample 0 is easy, we do
// x[7]     ->      A(z^-2)
// x[1]     ->      D(z^-1)     --> MREG(z^-1)--+
//                                              |
// x[0]     ->      A(z^-1)     --> MREG(z^-1> -+---- PREG(z^-1)
// still again giving the same z^-3 delay
//
// for sample 7 we need effort:
// x[7]     ->      A(z^-1)     --> MREG(z^-1)-+
//                                             |
// x[6]     ->      A(z^-2)-----+--------------+---- PREG (z^-1)
// x[0]     ->      D(z^-1)-----|
// This still leaves z^-3 timing but note that the x[0] multiplier has z^-2 timing.
// e.g. we get
// (coeff1*x[7]z^-2 + coeff0(x[6]z^-2 + x[0]z^-1))z^-1
//
// The bypass input does 2 things. It forces dspA's MREG in reset OR
// swaps the inmode for the multiplier to zero. It also swaps the inmode
// on dspB to multiply by D, which is 1.
// 
// There are timing variations on this though. Consider resetting dspA's MREG.
// clk  RSTM        MREG    PREG on dspB
// 0    0           M[-2]   P[-3]
// 1    1           M[-1]   P[-2]
// 2    1           0       P[-1]
// 3    1           0       0
// 4    0           0       0
// 5    0           M[3]    0
// 6    0           M[4]    P[3]
// now consider sample NSAMP-1, controlled by INMODE swapping with no MREG.
// clk  bypass      INMODE  INMODEREG   PREG on dspA
// 0    0           5'd4    5'd4        P[-3]
// 1    1           5'd2    5'd4        P[-2]
// 2    1           5'd2    5'd2        P[-1]
// 3    1           5'd2    5'd2        0
// 4    0           5'd4    5'd2        0
// 5    0           5'd4    5'd4        0
// 6    0           5'd4    5'd4        P[3]
// These two line up well because both are controlling a register that
// then controls PREG.
// NSAMP-1's dspA_inmode is just either 00100 or 00010. We handle this
// by { 2'b00, bypass_i, bypass_i, 1'b0 }
// and IS_INMODE_INVERTED = 5'b00100;

// Now consider dspB's bypass input.
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

// n.b. this kinda seems dumb like I should be able to shunt
// up A instead of routing it, dude. Technically I probably should be able to avoid
// an A register entirely??
//
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
      
   reg bypass_rereg = 0;
   always @(posedge clk) begin
        bypass_rereg <= bypass_i;
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

        wire [NBITS-1:0] future_samp = dat_i[NBITS*((i+1)%NSAMP) +: NBITS];
        wire [NBITS-1:0] this_samp = dat_i[NBITS*i +: NBITS];
        wire [NBITS-1:0] last_samp = dat_i[NBITS*((i+NSAMP-1)%NSAMP) +: NBITS];

        // The FIR DSP core doesn't work for all of our trickery,
        // sadly. The last sample (NSAMP-1) has its DSPs flipped (B comes before A)
        // so it needs to be direct.
        localparam dspA_A_INPUT = (i == 0 || i == (NSAMP-1)) ? "DIRECT" : "CASCADE";
        localparam dspA_B_INPUT = (i == 0) ? "DIRECT" : "CASCADE";
        localparam dspA_AREG = (i == 0 || i == (NSAMP-1)) ? 2 : 0;        
        wire [8:0] dspA_OPMODE = (i != (NSAMP-1)) ?
            { `W_OPMODE_0, `Z_OPMODE_0, `XY_OPMODE_M } :
            { `W_OPMODE_0, `Z_OPMODE_PCIN, `XY_OPMODE_M };

        wire [8:0] dspB_OPMODE = (i != (NSAMP-1)) ?
            { `W_OPMODE_0, `Z_OPMODE_PCIN, `XY_OPMODE_M } :
            { `W_OPMODE_0, `Z_OPMODE_0, `XY_OPMODE_M };
                        
        wire [3:0] dspA_ALUMODE = `ALUMODE_SUM_ZXYCIN;        
        wire [3:0] dspB_ALUMODE = `ALUMODE_SUM_ZXYCIN;

        // The way our trickery works is that dspB is configured to flip between
        // B2 and D, which is insane that that works. But it does!
        // BMULTSEL = AD
        // AMULTSEL = A
        // PREADDINSEL = B
        wire [4:0] dspB_INMODE = { 2'b00, bypass_i, bypass_i, 1'b0 };
        // for nsamp-1 it also uses dspB_INMODE but instead flops to zero
        // using the inversion
        wire [4:0] dspA_INMODE = (i == (NSAMP-1)) ?
            { 2'b00, bypass_rereg, bypass_rereg, 1'b0 } :
            5'b00100;

        // D is (1<<14). The INMODE control
        // swaps between 1 and coeff1
        wire [26:0] dspB_D = 26'd16384;
        wire [29:0] dspB_A = { {A_SIGNEXTEND{this_samp[NBITS-1]}}, this_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };

        `define COMMON_DSPA_ATTRS   .A_INPUT(dspA_A_INPUT), \
                                    .B_INPUT(dspA_B_INPUT), \
                                    .AREG( dspA_AREG ),     \
                                    .DREG(1),               \
                                    .ADREG(0),              \
                                    .AMULTSEL("AD"),        \
                                    .BMULTSEL("B"),         \
                                    .PREADDINSEL("A"),      \
                                    `COMMON_ATTRS

        `define COMMON_DSPB_ATTRS   .B_INPUT("CASCADE"),    \
                                    .A_INPUT("DIRECT"),     \
                                    .AREG(1),               \
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
                       .MREG(1),
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
            wire [26:0] dspA_D = { {D_SIGNEXTEND{future_samp[NBITS-1]}}, future_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
            DSP48E2 #( `COMMON_DSPA_ATTRS,
                       .ACASCREG(0),
                       .INMODEREG(0),
                       .MREG(1),
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
                // i == NSAMP-1 has reversed ordering - dspA comes last so we can skip MREG. But now we have
                // PREG and INMODEREG.
                wire [29:0] dspA_A = { {A_SIGNEXTEND{last_samp[NBITS-1]}}, last_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
                wire [26:0] dspA_D = { {D_SIGNEXTEND{future_samp[NBITS-1]}}, future_samp, {(AD_FRAC_BITS-NFRAC){1'b0}} };
                // IS_INMODE_INVERTED = 5'b00100
                DSP48E2 #( `COMMON_DSPA_ATTRS,
                           .INMODEREG(1),
                           // bit 
                           .IS_INMODE_INVERTED( 5'b00100 ),
                           .MREG(0),
                           .PREG(1) )
                    u_dspA( .A(dspA_A),
                            .BCIN(internal_bcascade),
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
                            .CEINMODE( 1'b1 ),
                            .CED( 1'b1 ),
                            .CEP( 1'b1 ),
                            .RSTA(1'b0),
                            .RSTB(1'b0),
                            .RSTD(1'b0),
                            .RSTM(1'b0),
                            .RSTCTRL(1'b0),
                            .RSTALLCARRYIN(1'b0),
                            .RSTALUMODE(1'b0),
                            .RSTINMODE(1'b0),
                            .CLK(clk),
                            .PCIN(internal_pcascade),
                            .P( fir_out ));
            end
            if (i != (NSAMP-1)) begin : BBODY
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
            end else begin : BTAIL
                // For sample NSAMP-1 dspB comes first.
                DSP48E2 #( `COMMON_DSPB_ATTRS,
                           .PREG(0))
                    u_dspB( .A(dspB_A),
                            .BCIN(bcascade[i-1]),
                            `C_UNUSED_PORTS,
                            .D(dspB_D),
                            .OPMODE( dspB_OPMODE ),
                            .ALUMODE( dspB_ALUMODE ),
                            .CARRYIN(1'b0),
                            .CARRYINSEL(3'b000),
                            .INMODE( dspB_INMODE ),
                            .CEB1( coeff_wr_i ),
                            .CEB2( coeff_update_i ),
                            .CEA2( 1'b1 ),
                            .CEM( 1'b1 ),
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
                            .BCOUT( internal_bcascade ),
                            .PCOUT( internal_pcascade ));
            end
    	    assign dat_o[OUTBITS*i +: OUTBITS] = fir_out[ (P_FRAC_BITS-OUTFRAC) +: OUTBITS]; 
        end
    endgenerate                                          
endmodule
 
