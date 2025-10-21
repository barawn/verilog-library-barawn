`timescale 1ns / 1ps
`include "dsp_macros.vh"

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

// This is the compensating FIR for a biquad's pole pair.
// v2 rearranges things to reduce power consumption by sharing delays
// and passing the delayed inputs along for the incremental version.
//
// NOTE: we MAY want to test swapping between using the actual AREGs
// and fabric registers. The fabric registers may be lower power total
// because there are fewer bits flipping, since the actual AREGs have
// to sign extend.
//
// The compensating FIR consists of 2 separate FIRs, termed the
// f and g chain, along with an additional pair of DSPs which
// handle the pipelining (creating the F and G inputs).
//
// The f/g chain looks like:
// f = u[0] + c[0]u[NSAMP-1]z^-1 + c[1]u[NSAMP-2]z^-1 + ... c[NSAMP-3]u[2]z^-1
// g = u[1] + d[0]u[0] + d[1]u[NSAMP-1]z^-1 + d[2]u[NSAMP-2]z^-1 + ... d[NSAMP-2]u[2]z^-1
//
// In order to balance the delays in these inputs, we reorganize the DSPs. Each input
// picks up an additional clock, but in the incremental version there will be an additional
// clock delay as well with incrementing delays. So, for instance, sample 3 needs
// an additional delay after sample 2 to allow for time for it to be generated.
// Therefore we rearrange this as:
//
// f = u[0] + C[0]u[2]z^-1 + C[1]u[3]z^-1 + ...
// g = u[1] + D[0]u[0] + D[1]u[2]z^-1 + ...
//
// Note that because the f and g chains are different lengths, we need to align the
// f chain so that C[0]u[2]z^-1 and D[1]u[2]z^-1 have the same timing.
//
// Consider the output of the first f DSP with AREG=1, ADREG=0, MREG=1
// dsp_f0 = (u[0]z^-1 + C[0](u[2]z^-1)z^-1)z^-1 = (u[0] + C[0]u[2]z^-1)z^-2 = f0z^-2
// Following through the first g DSP with AREG=1, MREG=0
// dsp_g0 = (u[1]z^-1 + D[0]u[0]z^-1)z^-1 = (u[1] + D[0]u[0])z^-2 = g0z^-2
// and the second g DSP with AREG=2, MREG=1
// dsp_g1 = (g0z^-2 + (D[1]u[2]z^-2z^-1))z^-1 = (g0z^-2 + g1z^-2)z^-1 = (g0+g1)z^-3
// Therefore clearly we need to bump up an additional register in the f DSP, so go to AREG=2
// which requires adjusting the input to u[0]z^-1
//
// Therefore the f chain will have AREG=2, ADREG=0, MREG=1
// The first DSP in the g chain will have AREG=1, MREG=0 and the remainder AREG=2, MREG=1.
// We now have
// dsp_f0 = ((u[0]z^-1)z^-1 + C[0](u[2]z^-2)z^-1)z^-1 = (u[0] + C[0]u[2]z^-1)z^-3 = f0z^-3
// dsp_g0 = g0z^-2
// dsp_g1 = (g0+g1)z^-3
// And then dsp_f1 takes in C[1]u[3]z^-1, giving
// dsp_f1 = (f0z^-3 + C[1]((u[3]z^-1)z^-2)z^-1)z^-1 = (f0 + C[1]u[3]z^-1)z^-4
// dsp_g2 = ((g0+g1)z^-3 + D[2](u[3]z^-1)z^-2)z^-1)z^-1 = (g0+g1+D[2]u[3]z^-1)z^-4
// which gives us the alignment we want.
// Also note that our delayed outputs will have:
// u[2]
// u[3]z^-1
// u[4]z^-2 etc. etc.
//
// The DSPs that generate the F and G chain don't change. This means our coefficients
// programmed in are actually:
//
// F chain:     (-P^M)*U_(M-2)(cos t)
//              P*U_1(cos t) ..             (coeff for x[M-2])
//              P^(M-2)U_(M-2)(cos t)       (coeff for x[2])
// G chain:     P^M*U_M(cos t)
//              P^2 U_(M-2)(cos t)          (coeff for x[M-1])
//              ...
//              P^(M-1)U_(M-1)(cos t)       (coeff for x[2])
//              P*U_1(cos t)                (coeff for x[0])
module biquad8_pole_fir_v2 #(parameter NBITS=16, 
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
        output [47:0]		y1_out,
        // Delayed versions of the input, with increasing delays.
        // Each input past 2 has (sample-2) clocks of delay.
        output [NBITS*NSAMP-1:0] x_out
    );
    
    // Total length of the F chain = (f length + 1)
    localparam FLEN = NSAMP-1;
    // Total length of the G chain = (g length + 1)
    localparam GLEN = NSAMP;
    
    // Outputs and cascades from the F chain    
    wire [47:0] fpout[FLEN-1:0];
    wire [17:0] fbcascade[FLEN-1:0];
    wire [47:0] fpcascade[FLEN-1:0];
    // Outputs and cascades from the G chain
    wire [17:0] gbcascade[GLEN-1:0];
    wire [47:0] gpcascade[GLEN-1:0];
    wire [47:0] gpout[GLEN-1:0];
    
    // Registered control signals.
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg coeff_wr_f = 0;
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg coeff_wr_g = 0;
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg	coeff_wr_fcross = 0;
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg	coeff_wr_gcross = 0;   
  
    // Update all coefficients.
    reg update = 0;

    // Logic for coefficient control.
    always @(posedge clk) begin
       coeff_wr_f <= coeff_wr_i && (coeff_adr_i == 2'b00);       
       coeff_wr_g <= coeff_wr_i && (coeff_adr_i == 2'b01);

       update <= coeff_update_i;

       coeff_wr_fcross <= coeff_wr_i && (coeff_adr_i == 2'b10);
       coeff_wr_gcross <= coeff_wr_i && (coeff_adr_i == 2'b11);       
    end

    `define COMMON_ATTRS    `CONSTANT_MODE_ATTRS, `DE2_UNUSED_ATTRS, .BREG(2), .BCASCREG(1), .PREG(1)    

    // CHEAP IMPROVEMENT
    // What we were PREVIOUSLY doing was 
    // 7    -> SRL(A=2)->FF ->  F dspA_in[0]
    //      -> SRL(A=1)->FF ->  G dspA_in[1]
    // 6    -> SRL(A=3)->FF ->  F dspA_in[1]
    //      -> SRL(A=2)->FF ->  G dspA_in[2]
    // etc.
    // This is obviously dumb. We can just do
    // 7    -> SRL(A=1)->FF ->  G dspA_in[1]
    //                   |--->  F dspA_in[0] with an extra AREG.
    //
    // Additionally, there's no reason for us to arrange the chains in any particular order at all.
    // Note that here, we end up with sample 7 with the shortest delays,
    // then sample 6, then sample 5, etc.
    // But for the incremental computation portion, sample 7 will end up needing the longest delay.
    // So instead, reverse this. It's just a change of programming parameters. And then actually
    // output all of the delayed values so we can reuse them in the incremental without
    // adding more delays.
    
    wire [NSAMP-1:0][NBITS-1:0] in_delayed;  
    
    localparam NUM_HEAD_PAD = 17 - (NBITS-NFRAC);
    localparam NUM_TAIL_PAD = 13 - NFRAC;
    
    generate    
        genvar fi,fj, gi,gj, smp;
        // Generate the delayed inputs.
        // sample 0 :   undelayed
        // sample 1 :   undelayed
        // sample 2 :   undelayed
        // sample 3 :   z^-1
        // sample 4 :   z^-2 
        // etc.
        for (smp=0;smp<NSAMP;smp=smp+1) begin : DLY
            if (smp < 3) begin : NODLY
                assign in_delayed[smp] = dat_i[NBITS*smp +: NBITS];                
            end else begin : DLY
                wire [NBITS-1:0] srl_out;
                reg [NBITS-1:0] dat_store = {NBITS{1'b0}};
                if (smp < 4) begin : NOSRL
                    assign srl_out = dat_i[NBITS*smp +: NBITS];
                end else begin : SRL
                    srlvec #(.WIDTH(NBITS))
                        u_srl(.clk(clk),.ce(1'b1),.a(smp-4),
                              .din(dat_i[NBITS*smp +: NBITS]),
                              .dout(srl_out));
                end
                always @(posedge clk) begin : STORE
                    dat_store <= srl_out;
                end
                assign in_delayed[smp] = dat_store;
            end
            assign x_out[NBITS*smp +: NBITS] = in_delayed[smp];
        end
        // Now run the f chain.        
        for (fi=0;fi<FLEN;fi=fi+1) begin : FLOOP
            // F chain has AREG=2, ADREG=0, MREG=1
            wire [29:0] dspA_in = (fi < FLEN-1) ?
                { {NUM_HEAD_PAD{in_delayed[fi+2][NBITS-1]}}, in_delayed[fi+2], {NUM_TAIL_PAD{1'b0}} } :
                  fpout[fi-1][14 +: 30];

            if (fi == 0) begin : HEAD
                localparam THIS_AREG = 0;
                localparam C_HEAD_PAD = 21 - (NBITS-NFRAC);
                localparam C_TAIL_PAD = 27 - NFRAC;
                // Need an extra clock in the C path to line everything up.
                reg [NBITS-1:0] in_store = {NBITS{1'b0}};
                always @(posedge clk) begin : ST
                    in_store <= in_delayed[0];
                end                
                wire [47:0] dspC_in = { {C_HEAD_PAD{in_store[NBITS-1]}}, in_store, {C_TAIL_PAD{1'b0}} };
                // the f chain will have AREG=2, ADREG=0, MREG=1
                (* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #(`COMMON_ATTRS,
                          .CREG(1),
                          .AREG(2),
                          .ACASCREG(2),
                          .ADREG(0),
                          .MREG(1))
                    u_head( .CLK(clk),
                            .CEP(1'b1),
                            .CEC(1'b1),
                            .CEM(1'b1),
                            .CEA1(1'b1),
                            .CEA2(1'b1),
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
                localparam THIS_AREG = (fi < FLEN-1) ? 2 : 0;
                wire THIS_CEA = (fi < FLEN-1) ? 1 : 0;
                DSP48E2 #(`COMMON_ATTRS,
                          `C_UNUSED_ATTRS,
                          .B_INPUT("CASCADE"),
                          .AREG(THIS_AREG),
                          .ACASCREG(THIS_AREG),
                          .ADREG(0),
                          .MREG(1))
                    u_body( .CLK(clk),
                            .CEP(1'b1),                            
                            .A(dspA_in),
                            .CEA2(THIS_CEA),
                            .CEA1(THIS_CEA),
                            .CEM(1'b1),
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
        // And the g chain
        for (gi=0;gi<GLEN;gi=gi+1) begin : GLOOP
            localparam int IDX = (gi > 0) ? gi+1 : 0;            
            wire [29:0] dspA_in;
            assign dspA_in = (gi < GLEN-1) ? 
                { {NUM_HEAD_PAD{in_delayed[IDX][NBITS-1]}}, in_delayed[IDX], {NUM_TAIL_PAD{1'b0}} } :
                  gpout[gi-1][14 +: 30];

            // head gets AREG=1, MREG=0
            if (gi == 0) begin : HEAD
                localparam C_HEAD_PAD = 21 - (NBITS-NFRAC);
                localparam C_TAIL_PAD = 27 - NFRAC;
                wire [47:0] dspC_in = { {C_HEAD_PAD{in_delayed[1][NBITS-1]}}, in_delayed[1], {C_TAIL_PAD{1'b0}} }; 
                // HEAD dsp gets its inputs directly
                (* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #(`COMMON_ATTRS,
                          .CREG(1),
                          .AREG(1),
                          .ADREG(0),
                          .ACASCREG(1),
                          .MREG(0))                          
                    u_head( .CLK(clk),
                            .CEP(1'b1),
                            .CEA2(1'b1),
                            .CEC(1'b1),
                            .CEM(1'b1),
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
                // and everywhere else gets AREG=2, MREG=1 except the loopback which gets AREG=0           
                localparam THIS_AREG = (gi < GLEN-1) ? 2 : 0;
                wire THIS_CEA = (gi < GLEN-1) ? 1 : 0;
                DSP48E2 #(`COMMON_ATTRS,
                          .AREG(THIS_AREG),
                          .ACASCREG(THIS_AREG),
                          .MREG(1),
                          .B_INPUT("CASCADE"),
                          `C_UNUSED_ATTRS)
                    u_body( .CLK(clk),
                            .CEP(1'b1),
                            .CEA1(THIS_CEA),
                            .CEA2(THIS_CEA),
                            .CEM(1'b1),
                            .A(dspA_in),
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

