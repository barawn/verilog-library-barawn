`timescale 1ns / 1ps
`include "dsp_macros.vh"

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

// Updated to handle multiple sample rate options.
// The F chain is NSAMP-1 samples long.
// The G chain is NSAMP samples long.

// FIR portion of a pole-only biquad operating at 8x clock rate.
// The FIRs are 6 and 7 taps long initially, have an additional
// DSP where one loop-back is done, and so are functionally 7 and 8 taps long.
// They then have an additional 2 DSPs where they're crossed
// together, and the outputs of *those* go straight to the recursive
// guys to be added in.
// The recursive guys drive the timing so we let them be in a 4-DSP chain.
// We therefore have 17 DSPs.
//
// Programming is always done by chain. We effectively have 4 chains.
// F chain, G chain, F cross-link, G cross-link
//
// By chain means you need to write to the same address multiple times
// to load the coefficients.
//
// F chain is P^nU(n,cost) up to 6, then -1*P^8 U(6, cost)
// G chain is P^nU(n,cost) up to 7, then P^8 U(8,cost)
// F cross-link is P^7 U(7, cost)
// G cross-link is P^9 U(7, cost)
//
// addr 00:
// write coeff 6: -1*P^8 U(6, cost) D_FF
// write coeff 5: P^6 U(6, cost)
// write coeff 4: P^5 U(5, cost)
// write coeff 3: P^4 U(4, cost)
// write coeff 2: P^3 U(3, cost)
// write coeff 1: P^2 U(2, cost)
// write coeff 0: P   U(1, cost)
// update
// addr 01:
// write coeff 7: P^8 U(8, cost) E_GG
// write coeff 6: P^7 U(7, cost)
// write coeff 5: P^6 U(6, cost)
// write coeff 4: P^5 U(5, cost)
// write coeff 3: P^4 U(4, cost)
// write coeff 2: P^3 U(3, cost)
// write coeff 1: P^2 U(2, cost)
// write coeff 0: P   U(1, cost)
// update
// addr 02:
// write P^7 U(7, cost), update
// addr 03:
// write P^9 U(7, cost), update
module biquad8_pole_fir #(parameter NBITS=16, 
                          parameter NFRAC=2,
                          parameter CLKTYPE="NONE",
                          parameter NSAMP=8) (
        input			clk,
        input [NBITS*NSAMP-1:0]	dat_i,

	// the address here selects
	// 00 : F chain
	// 01 : G chain
	// 10 : F cross-link
	// 11 : G cross-link
	input [1:0]		coeff_adr_i, 
        input			coeff_wr_i,
        input			coeff_update_i,
        input [17:0]		coeff_dat_i,
                
        output [47:0]		y0_out,
        output [47:0]		y1_out
    );
    
    // F-chain first. All inputs are registered at the inputs to the IIR. Later inputs have delays.
    // Note that we're *shorter* than the G-chain, so our outputs would be 1 ahead. To fix that, we
    // add 1 to their delays, and enable CREG as well.
    //
    // Starting at clock 1, our coefficients are
    // 0 in[7]z^-1 * PU(1,cost)       output at clock 3   (SRL=1) (in[0] gets FF only and is stored in C)
    // 1 in[6]z^-1 * P^2 U(2, cost)   output at clock 4   (SRL=2)
    // 2 in[5]z^-1 * P^3 U(3, cost)   output at clock 5   (SRL=3)
    // 3 in[4]z^-1 * P^4 U(4, cost)   output at clock 6   (SRL=4)
    // 4 in[3]z^-1 * P^5 U(5, cost)   output at clock 7   (SRL=5)
    // 5 in[2]z^-1 * P^6 U(6, cost)   output at clock 8   (SRL=6)
    // 6 out5 z^-1 * -1*P^8 U(6, cost)   output at clock 9
    // 7 is the cross-link = g[n-1] * P^7 U(7, cost)
    //
    //
    // G-chain is
    // 16 in[0]*PU(1,cost)           output at clock 2
    // 17 in[7]z^-1 * P^2(U2,cost)   output at clock 3 (SRL=2)
    // ..
    // 22 in[2]z^-1 * P^7 U(7, cost) output at clock 8 (SRL=7)
    // 29 out22 z^-1 * P^8 U(8, cost) output at clock 9
    // 30 is the cross-link = f[n-1] * -1*P^9 U(7, cost)
    //
    // HEAD DSP only
    // clock    fin_store   Creg        dat_out     dat_store   dspP
    // 0        in[0][-1]   in[0][-2]   in[7][-2]   in[7][-3]   B*in[7][-4] + in[0][-3]
    // 1        in[0][0]    in[0][-1]   in[7][-1]   in[7][-2]   B*in[7][-3] + in[0][-2]
    // 2        in[0][1]    in[0][0]    in[7][0]    in[7][-1]   B*in[7][-2] + in[0][-1]
    // 3                                                        B*in[7][-1] + in[0][0]
    // G-chain HEAD DSP. This one has no SRL at HEAD.
    // clock    gin_store   dat_out     dspP
    // 0        in[1][-1]   in[0][-1]   B*in[0][-2] + in[1][-2]
    // 1        in[1][0]    in[0][0]    B*in[0][-1] + in[1][-1]
    // 2        in[1][1]    in[0][1]    B*in[0][0] + in[1][0]
    // so obviously the F-chain is one behind.
    // G-chain DSP1.
    // clock    PCIN                dat_store   dat_out     dspP
    // 2        B*in[0][0]+in[1][0] in[7][-1]   in[7][0]   B2*in[7][-2] + B*in[0][-1] + in[1][-1]
    // so in[7] needs an SRL delay of 2
    
    
    localparam FLEN = NSAMP-1;
    localparam GLEN = NSAMP;
    
    wire [47:0] fpout[FLEN-1:0];
    wire [17:0] fbcascade[FLEN-1:0];
    wire [47:0] fpcascade[FLEN-1:0];
    wire [17:0] gbcascade[GLEN-1:0];
    wire [47:0] gpcascade[GLEN-1:0];
    wire [47:0] gpout[GLEN-1:0];
    
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg coeff_wr_f = 0;
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg coeff_wr_g = 0;
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg	coeff_wr_fcross = 0;
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg	coeff_wr_gcross = 0;   
  
    reg [NBITS-1:0] fin_store = {NBITS{1'b0}};
    reg [NBITS-1:0] fin_store_tmp = {NBITS{1'b0}};
    reg [NBITS-1:0] gin_store = {NBITS{1'b0}};
    // Sigh. I originally had these in the loops, but they're
    // optimized out for some reason. Just put them here so
    // maybe I can figure out what's going on.
    // Optimizer will replicate this as needed hopefully.
    // Otherwise I can put a max fanout req on it.
    reg update = 0;

    always @(posedge clk) begin
       coeff_wr_f <= coeff_wr_i && (coeff_adr_i == 2'b00);       
       coeff_wr_g <= coeff_wr_i && (coeff_adr_i == 2'b01);

       update <= coeff_update_i;

       coeff_wr_fcross <= coeff_wr_i && (coeff_adr_i == 2'b10);
       coeff_wr_gcross <= coeff_wr_i && (coeff_adr_i == 2'b11);       
        
        // The F-chain (used for computing sample 0) takes sample 0. However,
        // it's *shorter* than the G-chain, and so we need to delay it more to
        // get things to line up. Note that this means that all of the SRLs
        // for the F-chain need an extra delay.
        fin_store_tmp <= dat_i[NBITS*0 +: NBITS];
        fin_store <= fin_store_tmp;
        // The G-chain (used for computing sample 1) takes sample 1
        gin_store <= dat_i[NBITS*1 +: NBITS];
    end

    // AREG is *almost* common. The next-to-last DSP in the chain
    // feeds back, and so obviously it needs a delay. But because
    // ACASCREG (pointlessly) needs to be AREG, we create a new
    // parameter for it.    
    `define COMMON_ATTRS( NAREG ) `CONSTANT_MODE_ATTRS,`DE2_UNUSED_ATTRS,.AREG( NAREG ),.ACASCREG( NAREG ),.ADREG(0),.BREG(2),.BCASCREG(1),.MREG(0),.PREG(1)

    generate
        genvar fi,fj, gi,gj;
        for (fi=0;fi<FLEN;fi=fi+1) begin : FLOOP
            wire [29:0] dspA_in;

            if (fi < FLEN-1) begin : DIRECT
                reg [NBITS-1:0] dat_store = {NBITS{1'b0}};
                wire [NBITS-1:0] dat_out;
                always @(posedge clk) begin : STORE
                    dat_store <= dat_out;
                end
	            // Select the input. Chain is arranged backwards.
	            wire [NBITS-1:0] data_in = (dat_i[NBITS*(NSAMP-1-fi) +: NBITS]);	       
                // Here's that extra delay for the F-chain data inputs.
                srlvec #(.NBITS(NBITS)) u_delay(.clk(clk),.ce(1'b1),.a(fi+2),
                                                .din(data_in),
                                                .dout(dat_out));
                // we get inputs in Q14.2 format. (NBITS-NFRAC, NFRAC)
                // Internally we compute in Q21.27 format, coefficients in Q4.14 format
                // So we shift to Q17.13 format.                                     
                localparam NUM_HEAD_PAD = 17 - (NBITS-NFRAC);
                localparam NUM_TAIL_PAD = 13 - NFRAC;
                assign dspA_in = { {NUM_HEAD_PAD{dat_store[NBITS-1]}}, dat_store, {NUM_TAIL_PAD{1'b0}} };            
            end else begin : LOOPBACK
                // The output is Q21.27, and we want
                // Q17.13.
                assign dspA_in = fpout[fi-1][14 +: 30];
            end
            if (fi == 0) begin : HEAD
                localparam THIS_AREG = 0;
                localparam C_HEAD_PAD = 21 - (NBITS-NFRAC);
                localparam C_TAIL_PAD = 27 - NFRAC;
                wire [47:0] dspC_in = { {C_HEAD_PAD{fin_store[NBITS-1]}}, fin_store, {C_TAIL_PAD{1'b0}} };
                // HEAD dsp gets its inputs directly
                // We don't need a CEA b/c it isn't registered.
                (* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #(`COMMON_ATTRS( THIS_AREG ),.CREG(1)) 
                    u_head( .CLK(clk),
                            .CEP(1'b1),
                            .CEC(1'b1),
                            .C(dspC_in),   // This is where the 1 in [1,X_1,X_2,...] is added             
                            .A(dspA_in),
                            .B(coeff_dat_i),
                            .BCOUT(fbcascade[fi]),
                            .CEB1(coeff_wr_f),  // The first clock enable allows the new coefficients to flow in (but not apply)
                            .CEB2(update),      // The second clock eneable applies the coefficients
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                            .OPMODE( { 2'b00, `Z_OPMODE_C, `XY_OPMODE_M } ),
                            .INMODE( 0 ),
                            .P(fpout[fi]),
                            .PCOUT(fpcascade[fi]));
            end else begin : BODY
                localparam THIS_AREG = (fi < FLEN-1) ? 0 : 1;
                DSP48E2 #(`COMMON_ATTRS( THIS_AREG ),.B_INPUT("CASCADE"),`C_UNUSED_ATTRS)
                    u_body( .CLK(clk),
                            .CEP(1'b1),                            
                            .A(dspA_in),
                            .CEA2(THIS_AREG),
                            .BCIN(fbcascade[fi-1]),
                            .BCOUT(fbcascade[fi]),
                            .CEB1(coeff_wr_f),
                            .CEB2(update),
                            `C_UNUSED_PORTS,
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                            .OPMODE( { 2'b00, `Z_OPMODE_PCIN, `XY_OPMODE_M } ),
                            .INMODE( 0 ),
                            .P(fpout[fi]),
                            .PCIN(fpcascade[fi-1]),
                            .PCOUT(fpcascade[fi]) );
            end 
        end
        for (gi=0;gi<GLEN;gi=gi+1) begin : GLOOP
            wire [29:0] dspA_in;
            if (gi < GLEN-1) begin : DIRECT
                reg [NBITS-1:0] dat_store = {NBITS{1'b0}};
                wire [NBITS-1:0] dat_out;
                if (gi > 0) begin : SRL
	                wire [NBITS-1:0] data_in = (dat_i[NBITS*(NSAMP-gi) +: NBITS]);
                    srlvec #(.NBITS(NBITS)) u_delay(.clk(clk),.ce(1'b1),.a(gi+1),
                                                    .din(data_in),
                                                    .dout(dat_out));
                    always @(posedge clk) begin : STORE
                        dat_store <= dat_out;
                    end                                    
                end else begin : FF
                    // We grab the *undelayed* input.
                    always @(posedge clk) begin : STORE
                        dat_store <= fin_store_tmp[0 +: NBITS];
                    end
                end
                // we get inputs in Q14.2 format. (NBITS-NFRAC, NFRAC)
                // Internally we compute in Q21.27 format, coefficients in Q4.14 format
                // So we shift to Q17.13 format.                                     
                localparam NUM_HEAD_PAD = 17 - (NBITS-NFRAC);
                localparam NUM_TAIL_PAD = 13 - NFRAC;
                assign dspA_in = { {NUM_HEAD_PAD{dat_store[NBITS-1]}}, dat_store, {NUM_TAIL_PAD{1'b0}} };            
            end else begin : LOOPBACK
                assign dspA_in = gpout[gi-1][14 +: 30];
            end
            if (gi == 0) begin : HEAD
                localparam THIS_AREG = 0;
                localparam C_HEAD_PAD = 21 - (NBITS-NFRAC);
                localparam C_TAIL_PAD = 27 - NFRAC;
                wire [47:0] dspC_in = { {C_HEAD_PAD{gin_store[NBITS-1]}}, gin_store, {C_TAIL_PAD{1'b0}} }; 
                // HEAD dsp gets its inputs directly
                (* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #(`COMMON_ATTRS(THIS_AREG),.CREG(1)) 
                    u_head( .CLK(clk),
                            .CEP(1'b1),
                            .CEC(1'b1),
                            .C(dspC_in),                            
                            .A(dspA_in),
                            .B(coeff_dat_i),
                            .BCOUT(gbcascade[gi]),
                            .CEB1(coeff_wr_g),
                            .CEB2(update),
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                            .OPMODE( { 2'b00, `Z_OPMODE_C, `XY_OPMODE_M } ),
                            .INMODE( 0 ),
                            .P(gpout[gi]),
                            .PCOUT(gpcascade[gi]));
            end else begin : BODY
                localparam THIS_AREG = (gi < GLEN-1) ? 0 : 1;
                DSP48E2 #(`COMMON_ATTRS(THIS_AREG),.B_INPUT("CASCADE"),`C_UNUSED_ATTRS)
                    u_body( .CLK(clk),
                            .CEP(1'b1),
                            .A(dspA_in),
                            .CEA2(THIS_AREG),
                            .BCIN(gbcascade[gi-1]),
                            .BCOUT(gbcascade[gi]),
                            .CEB1(coeff_wr_g),
                            .CEB2(update),
                            `C_UNUSED_PORTS,
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                            .OPMODE( { 2'b00, `Z_OPMODE_PCIN, `XY_OPMODE_M } ),
                            .INMODE( 0 ),
                            .P(gpout[gi]),
                            .PCIN(gpcascade[gi-1]),
                            .PCOUT(gpcascade[gi]) );
            end 
        end
    endgenerate                            
    // Now our final two cross-linked DSPs take fpout[FLEN-2] (=f[n]) and fpout[FLEN-1] = (f[n-1] + B*f[n-2]).
    //
    // We ** might ** want to actually put dspF at the end of the G chain and dspG at the end of the F chain.
    // Right now for instance both GLOOP[7] and dspF both take the same inputs with delay, so there's no reason
    // we couldn't cascade the input there.
    //     
    // plus the equivalent from the G-chain.
    // We want B2*g[n-1] + f[n] + B*f[n-1].
    // So we drop fpout[FLEN-1] into C (meaning it contains f[n-2] and B*f[n-3])
    // and drop gpout[GLEN-2] into A with 2 regs + MREG, meaning
    // A1 contains g[n-1]
    // A2 contains g[n-2]
    // MREG contains B*g[n-3]
    // and equivalent.
    wire ceb1_f = coeff_wr_fcross;
    wire ceb1_g = coeff_wr_gcross;
    (* KEEP = "TRUE" *)
    reg ceb2_f = 0;
    (* KEEP = "TRUE" *)
    reg ceb2_g = 0;
    always @(posedge clk) begin
        ceb2_f <= coeff_update_i;
        ceb2_g <= coeff_update_i;
    end
    // A gets gpout[GLEN-2]
    localparam C_FRAC_BITS = 27;
    localparam A_FRAC_BITS = 13;
    // Then to find where A starts, you just subtract the difference between
    // the A and C frac bits (if they were the same, you start at the same one).
    // Here we drop the bottom 14 bits.
    wire [29:0] dspF_A = { gpout[GLEN-2][(C_FRAC_BITS-A_FRAC_BITS) +: 30] };
    wire [47:0] dspF_C = fpout[FLEN-1];
    (* CUSTOM_CC_DST = CLKTYPE *)
    DSP48E2 #(.AREG(2),.MREG(1),.BREG(2),.PREG(1),.CREG(1),`CONSTANT_MODE_ATTRS,`DE2_UNUSED_ATTRS)
        u_fdsp( .CLK(clk),
                .CEP(1'b1),
                .CEC(1'b1),
                .CEA1(1'b1),
                .CEA2(1'b1),
                .CEM(1'b1),
                .CEB1(ceb1_f),
                .CEB2(ceb2_f),
                .B(coeff_dat_i),
                .A(dspF_A),
                .C(dspF_C),
                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                .OPMODE( { 2'b00, `Z_OPMODE_C, `XY_OPMODE_M } ),
                .INMODE(0),
                .P(y0_out));
    // A gets fpout[GLEN-2]
    wire [29:0] dspG_A = { fpout[FLEN-2][(C_FRAC_BITS-A_FRAC_BITS) +: 30] };
    wire [47:0] dspG_C = gpout[GLEN-1];
    (* CUSTOM_CC_DST = CLKTYPE *)
    DSP48E2 #(.AREG(2),.MREG(1),.BREG(2),.PREG(1),.CREG(1),`CONSTANT_MODE_ATTRS,`DE2_UNUSED_ATTRS)
        u_gdsp( .CLK(clk),
                .CEP(1'b1),
                .CEC(1'b1),
                .CEA1(1'b1),
                .CEA2(1'b1),
                .CEM(1'b1),
                .CEB1(ceb1_g),
                .CEB2(ceb2_g),
                .B(coeff_dat_i),
                .A(dspG_A),
                .C(dspG_C),
                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                .OPMODE( { 2'b00, `Z_OPMODE_C, `XY_OPMODE_M } ),
                .INMODE(0),
                .P(y1_out));

    
    `undef COMMON_ATTRS
endmodule

