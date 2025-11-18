`include "dsp_macros.vh"
// Taken from https://github.com/barawn/pueo_tv/blob/main/hdl/dual_biquad/biquad8_incremental.v

// Big adjustments here to try to cut down on power.
// Instead of calculating things in two clocks in the DSPs
// (which accelerates the delays a lot), we instead
// take the two prior samples and register them at the MREG
// and add both in one clock.

// We're attempting to compute
// P = (coeff0*y[i-1] + coeff1*y[i-2] + x[i]).
// No matter what we're going to need 2 clocks per extra sample. That's the fastest we can do it.
// Little quicker on the first one though.
// Now inserting the sums, we want to insert them as early as possible to reduce delays. So into the first one.
//
// Just a common chain.
// dsp2_A:
//      y0  ->  AREG=1, MREG=1, A input = direct, PREG=0            = output = coeff0*y0z^-2 + x2z^-2
//  x2z^-1  ->  CREG=1
// dsp2_B:
//      y1  ->  AREG=1, MREG=1, A input = direct, PREG=1, ACASCREG=1 = output = (coeff0*y0z^-2 + coeff1*y1z^-2 + x2z^-2)z^-1 = y2z^-3
//                                                             cascade output = y1z^-1
// dsp3_A:
//          ->  AREG=2, A input = cascade, MREG=1, PREG=0           = output = coeff0*y1z^-4
//  x3z^-3  ->  CREG=1
// dsp3_B:
//      y2  ->  AREG=1, MREG=0, A input = direct, PREG=1, ACASCREG=1    = output = (coeff0*y1z^-4 + coeff1*y2z^-4)z^-1 = y3z^-5
//                                                              cascade output   = y2z^-4
// dsp4_A:
//          ->  AREG=1, A input = cascade, MREG=1, PREG=0           = output = coeff0*y2z^-6
//  x4z^-5  ->  CREG=1
// dsp4_B:
//      y3  ->  AREG=1, MREG=0, A input = direct, PREG=1, ACASCREG=1 = output = (coeff0*y2z^-6 + coeff1*y3z^-6)z^-1
// etc.
//
// We already need NSAMP+6-smp to get equal timing with y0/y1 outputs. We need (2*(smp-2)+1) = 2*smp-3 here.
// So in total we need NSAMP+6-smp + 2*smp -3 = NSAMP+smp+3 = (BASE_DELAY-3)+smp

// NOTE NOTE NOTE -
// We also want to look at allowing THESE outputs to stagger to absorb the delays needed in the pole FIR.
// This is slightly more complicated because the single zero FIR right now assumes everything comes in
// at the same clock, but we can absorb one delay there, and they still would be staggered by 1 output,
// meaning the pole FIR wouldn't need the delay staggering.
module biquad8_incremental_v2 #(
                             // X input format
                             parameter NBITS=16,
                             parameter NFRAC=2,
                             // Y input format
                             parameter NBITS2=30, // Note: this may not actually parameterize well at the moment
                             parameter NFRAC2=13,
                             parameter OUTBITS=12, // Note: this may not actually parameterize well at the moment
                             parameter OUTFRAC=0,
                             parameter NSAMP=8,
                             // This is how much delay x_in[0] (in theory!!) needs to line up with y0_in/y1_in. Every
                             // sample after that drops by one.
                             parameter X_DELAY = NSAMP+6,
			                 parameter CLKTYPE = "NONE")(
             input clk,
             input bypass_i,
             // These are now the delays AS FED THROUGH from the biquad8_pole_fir
             // In order to get them to line up with y0/y1, we need
             // (NSAMP+3)-smp clocks.
             input [NBITS*NSAMP-1:0] x_in,
             input [NBITS2-1:0] y0_in,
             input [NBITS2-1:0] y1_in,
                          
             input [17:0] coeff_dat_i,
             input coeff_wr_i,
             input coeff_update_i,
             
             output [OUTBITS*NSAMP-1:0] dat_o);

    // the bypass input comes from the pole FIR:
    // there are 5 clocks from it going high
    // until data becomes bypassed.

    localparam BYPASS_IIR_DELAY = 4;
    reg [BYPASS_IIR_DELAY:0] bypass_shreg = {(BYPASS_IIR_DELAY+1){1'b0}};
    
    always @(posedge clk) begin
        bypass_shreg <= { bypass_shreg[BYPASS_IIR_DELAY-1:0], bypass_i };
    end
    
    wire [NSAMP-1:2] force_bypass;
    wire force_bypass_in = bypass_shreg[BYPASS_IIR_DELAY];
    
    localparam C_FRAC_BITS = 27;
    localparam C_BITS = 48;
    localparam C_HEAD_PAD = (C_BITS-C_FRAC_BITS) - (NBITS-NFRAC);
    localparam C_TAIL_PAD = C_FRAC_BITS - NFRAC;
    // Q17.13. Passed around as Q14.10.
    localparam A_FRAC_BITS = 13;
    localparam A_BITS = 30;
    // The input is NBITS2 with NFRAC2 fractional bits.
    // Currently, this is assuming that the A ins are larger than the parameterizable input
    localparam A_HEAD_PAD = (A_BITS-A_FRAC_BITS) - (NBITS2-NFRAC2); // nominally zero
    localparam A_TAIL_PAD = A_FRAC_BITS - NFRAC2; // nominally zero

   
    // OK, we need lots of cascades. The extra ones will just be left alone.
    wire [17:0] bcascade[NSAMP-1:2];
    wire [29:0] acascade[NSAMP-1:2];
    wire [47:0] pout[NSAMP-1:2];

    // The TOTAL delay through everyone is 1 + (NSAMP-2)*2
    // e.g. for 4 it's 5, for 8 it's 13.
    localparam TOTAL_REALIGN_DELAY = 1 + (NSAMP-2)*2;

//    // Let's try using a distram delay for these. The old
//    // delay used TOTAL_REALIGN_DELAY+1 clocks. So if we do
//    // TOTAL_REALIGN_DELAY in a distram delay it'll match up exactly.
//    Our realign delays are:
//    y0/y1: 6 clocks
//    y2   : 4 clocks
//    y3   : 2 clocks
    
//    // Distram delays SHOULD be lower power because only 2 FFs toggle each
//    // clock. If this works we'll expand the distram to cover the input delays
//    // which have a big common delay (9 clocks) along with an additional FF
//    // for each.
//    wire [13:0] y0_out;
//    wire [13:0] y1_out;
    
//    distram14_delay #(.DELAY(TOTAL_REALIGN_DELAY),.NSAMP(2))
//        u_y01_delay(.clk_i(clk),
//                    .rst_i(1'b0),
//                    .dat_i( { 2'b00, y1_in[(NFRAC2-OUTFRAC) +: OUTBITS],
//                            2'b00, y0_in[(NFRAC2-OUTFRAC) +: OUTBITS] } ),
//                    .dat_o({ y1_out, y0_out }));
        
    // This is what y0/y1 need. Each sample needs TOTAL_REALIGN_DELAY-2*smp;        
    // we need to get the saturation stuff from the actual DSPs I think. The actual IIRs
    // won't saturate internally.
    reg [OUTBITS-1:0] y0_out = {OUTBITS{1'b0}};
    wire [OUTBITS-1:0] y0_srl;
    reg [OUTBITS-1:0] y1_out = {OUTBITS{1'b0}};
    wire [OUTBITS-1:0] y1_srl;    
    // This ends up being TOTAL_REALIGN_DELAY-1 because of the MREG
    // below: the C inputs take TOTAL_REALIGN_DELAY but when you
    // take the y inputs directly they're aligned one behind.
    srlvec #(.NBITS(OUTBITS))
        u_y0_srl(.clk(clk),.ce(1'b1),.a(TOTAL_REALIGN_DELAY-1),
                 .din(y0_in[(NFRAC2-OUTFRAC) +: OUTBITS]),
                 .dout(y0_srl));
    srlvec #(.NBITS(OUTBITS))
        u_y1_srl(.clk(clk),.ce(1'b1),.a(TOTAL_REALIGN_DELAY-1),
                 .din(y1_in[(NFRAC2-OUTFRAC) +: OUTBITS]),
                 .dout(y1_srl));                
    always @(posedge clk) begin
        y0_out <= y0_srl;
        y1_out <= y1_srl;
    end
    assign dat_o[0*OUTBITS +: OUTBITS] = y0_out[0 +: OUTBITS];
    assign dat_o[1*OUTBITS +: OUTBITS] = y1_out[0 +: OUTBITS];
    `define COMMON_ATTRS .BREG(2),.BCASCREG(1),`DE2_UNUSED_ATTRS,`CONSTANT_MODE_ATTRS
    generate
        genvar i;
        for (i=2;i<NSAMP;i=i+1) begin : INCR
            reg this_bypass = 0;
            always @(posedge clk) begin : LG
                this_bypass <= (i == 2) ? force_bypass_in : force_bypass[i-1];
            end
            assign force_bypass[i] = this_bypass;
            // internal cascades
            wire [17:0] b_cascade_internal;
            wire [47:0] p_cascade;
            // e.g. for sample 2 this is NSAMP+6-3+2 = NSAMP+5 = 9 clocks
            // The original delays were ABSURD - like for NSAMP=8 this was
            // 28/30/32/etc. clocks or something. For NSAMP=8 this is now
            // 13/14/15/16.
            localparam TOTAL_DELAY = X_DELAY - 3 + i;
            localparam SRL_DELAY = TOTAL_DELAY - 2;
            localparam REALIGN_DELAY = TOTAL_REALIGN_DELAY - 2*(i-1);
             
            wire [NBITS-1:0] dat_srl;
            reg [NBITS-1:0] dat_store = {NBITS{1'b0}};
            reg [NBITS-1:0] dat_realign = {NBITS{1'b0}};
            reg ceblow1 = 0;
            reg cebhigh1 = 0;
            reg ceblow2 = 0;
            reg cebhigh2 = 0;
            always @(posedge clk) begin : FF
                ceblow1 <= coeff_wr_i;
                cebhigh1 <= coeff_wr_i;
                ceblow2 <= coeff_update_i;
                cebhigh2 <= coeff_update_i;
            end

            srlvec #(.NBITS(NBITS)) u_dly(.clk(clk),.ce(1'b1),.a(SRL_DELAY),
                                          .din(x_in[NBITS*i +: NBITS]),
                                          .dout(dat_srl));
            always @(posedge clk) begin : DLY
                dat_store <= dat_srl;
            end                                          
            wire [47:0] dspC_in = { {C_HEAD_PAD{dat_store[NBITS-1]}}, dat_store, {C_TAIL_PAD{1'b0}} };
            if (i==2) begin : HEAD
                // dsp0 AREG=1, MREG=1, A input = direct, PREG=0
                // dsp1 AREG=1, MREG=1, A input = direct, PREG=1, ACASCREG=1
                wire [29:0] dsplowA_in = { {A_HEAD_PAD{y0_in[NBITS2-1]}},   y0_in,  {A_TAIL_PAD{1'b0}} }; 
                wire [29:0] dsphighA_in = {{A_HEAD_PAD{y1_in[NBITS2-1]}},   y1_in,  {A_TAIL_PAD{1'b0}} };                
                (* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #(`COMMON_ATTRS,
                          .B_INPUT("DIRECT"),
                          .AREG(1),.ACASCREG(1),.MREG(1),.PREG(0),.CREG(1))
                    u_dsplow(   `D_UNUSED_PORTS,
                                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                                .OPMODE( { 2'b00, `Z_OPMODE_C, `XY_OPMODE_M } ),
                                .INMODE(0),
                                .CLK(clk),
                                .CEM(1'b1),
                                .RSTM(this_bypass),
                                .CEB1(ceblow1),
                                .CEB2(ceblow2),
                                .CEA2(1'b1),
                                .CEC(1'b1),
                                .A(dsplowA_in),
                                .B(coeff_dat_i),
                                .C(dspC_in),
                                .PCOUT(p_cascade),
                                .BCOUT(b_cascade_internal) );
                DSP48E2 #(`COMMON_ATTRS,
                          `C_UNUSED_ATTRS,
                          .B_INPUT("CASCADE"),
                          .AREG(1),.MREG(1),.PREG(1),.ACASCREG(1))
                    u_dsphigh(  `D_UNUSED_PORTS,
                                `C_UNUSED_PORTS,
                                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                                .OPMODE( { 2'b00, `Z_OPMODE_PCIN, `XY_OPMODE_M } ),
                                .INMODE(0),
                                .CLK(clk),
                                .CEA2(1'b1),
                                .CEM(1'b1),
                                .RSTM(this_bypass),
                                .CEP(1'b1),
                                .CEB1(cebhigh1),
                                .CEB2(cebhigh2),
                                .A(dsphighA_in),
                                .PCIN(p_cascade),
                                .BCIN(b_cascade_internal),
                                .BCOUT(bcascade[i]),
                                .ACOUT(acascade[i]),
                                .P(pout[i]));
            end else begin : BODY                
                wire [NBITS2-1:0] dsp_high_in = pout[i-1][ (C_FRAC_BITS-NFRAC2) +: NBITS2 ];
                wire [29:0] dsphighA_in = {{A_HEAD_PAD{dsp_high_in[NBITS2-1]}},   dsp_high_in,  {A_TAIL_PAD{1'b0}} };                
                // dsp0 AREG=2, A input = cascade, MREG=1, PREG=0
                DSP48E2 #(`COMMON_ATTRS,
                          .B_INPUT("CASCADE"),
                          .A_INPUT("CASCADE"),
                          .AREG(2),
                          .MREG(1),
                          .PREG(0),
                          .CREG(1))
                    u_dsplow(   `D_UNUSED_PORTS,
                                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                                .OPMODE( { 2'b00, `Z_OPMODE_C, `XY_OPMODE_M } ),
                                .INMODE(0),
                                .CLK(clk),
                                .CEA2(1'b1),
                                .CEA1(1'b1),
                                .CEM(1'b1),
                                .RSTM(this_bypass),
                                .CEB1(ceblow1),
                                .CEB2(ceblow2),
                                .CEC(1'b1),
                                .C(dspC_in),
                                .BCIN(bcascade[i-1]),
                                .ACIN(acascade[i-1]),
                                .PCOUT(p_cascade),
                                .BCOUT(b_cascade_internal));                                
                // dsp1 AREG=1, MREG=0, A input = direct, PREG=1, ACASCREG=1
                DSP48E2 #(`COMMON_ATTRS,
                          `C_UNUSED_ATTRS,
                          .B_INPUT("CASCADE"),
                          .A_INPUT("DIRECT"),
                          .AREG(1),.MREG(0),.PREG(1),.ACASCREG(1))
                    u_dsphigh(  `D_UNUSED_PORTS,
                                `C_UNUSED_PORTS,
                                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                                .OPMODE( { 2'b00, `Z_OPMODE_PCIN, `XY_OPMODE_M } ),
                                .INMODE(0),
                                .CLK(clk),
                                .CEA2(1'b1),
                                .RSTA(this_bypass),
                                .CEB1(cebhigh1),
                                .CEB2(cebhigh2),
                                .CEP(1'b1),
                                .A(dsphighA_in),
                                .PCIN(p_cascade),
                                .BCIN(b_cascade_internal),
                                .BCOUT(bcascade[i]),
                                .ACOUT(acascade[i]),
                                .P(pout[i]));
            end
            // if this works we can handle saturation/rounding by adding an additional register
            // before this point.
            if (REALIGN_DELAY > 0) begin : RDLY
                reg [OUTBITS-1:0] dat_store = {OUTBITS{1'b0}};
                wire [OUTBITS-1:0] srl_out;
                if (REALIGN_DELAY > 1) begin : SRL
                    srlvec #(.NBITS(OUTBITS))
                        u_dly(.clk(clk),.ce(1'b1),.a(REALIGN_DELAY-2),
                              .din(pout[i][C_FRAC_BITS-NFRAC +: OUTBITS]),
                              .dout(srl_out));
                end else begin : NOSRL
                    assign srl_out = pout[i][C_FRAC_BITS-NFRAC +: OUTBITS];
                end
                always @(posedge clk) begin : ST
                    dat_store <= srl_out;
                end
                assign dat_o[OUTBITS*i +: OUTBITS] = dat_store;
            end else begin
                assign dat_o[OUTBITS*i +: OUTBITS] = pout[i][C_FRAC_BITS-NFRAC +: NBITS];
            end
        end
    endgenerate
            
endmodule
         
                             
