`timescale 1ns / 1ps
`define DLYFF #0.1
module shannon_whitaker_lpfull #(parameter NBITS=12,
                                 parameter OUTQ_INT = 12,
                                 parameter OUTQ_FRAC = 0,
                                 parameter NSAMPS=8)(
        input clk_i,
        input [NBITS*NSAMPS-1:0] in_i,
        output [(OUTQ_INT+OUTQ_FRAC)*NSAMPS-1:0] out_o
    );

    // coefficient definitions
    // NOTE: these are in Q3.15 format, so divide by 32768.

    // z^-15 and z^-17
    localparam [17:0] b_coeff15 = 10342;
    // z^-11/z^-21 and z^-13/z^-19
    localparam [17:0] b_coeff11_13 = 1672; // 13 is -1672*2+128
    // z^-9 and z^-23
    localparam [17:0] b_coeff9 = -949;
    // z^-5/z^-27 and z^-7/z^-25
    localparam [17:0] b_coeff5_7 = 263; // 5 is -2*263
    // z^-1/z^-31 and z^-3/z^-29
    localparam [17:0] b_coeff1_3 = -23; // 3 is 128-23
    
    // for ease of use
    wire [NBITS-1:0] xin[NSAMPS-1:0];
    generate
        genvar ii,jj;
        for (ii=0;ii<NSAMPS;ii=ii+1) begin : S
            for (jj=0;jj<NBITS;jj=jj+1) begin : B
                assign xin[ii][jj] = in_i[NBITS*ii + jj];
            end
        end
    endgenerate    
    
    // We generate 2 delayed inputs.
    wire [11:0] xin_store[7:0];      // these are at z^-8
    wire [11:0] xin_delay[7:0];      // these are at z^-32        
    
    // Convert between fixed point representations (this only works to EXPAND, not COMPRESS)
    `define QCONV( inval , SRC_QINT, SRC_QFRAC, DST_QINT, DST_QFRAC )   \
        ( { {( DST_QINT - SRC_QINT ) { inval[ (SRC_QINT+SRC_QFRAC) - 1 ] }}, inval, { ( DST_QFRAC - SRC_QFRAC ) {1'b0} } } )

    // The i11_13 DSPs need an input fed back to the i9 chain to be added at an earlier point for 2 of the taps.
    // Define this here for everyone.
    wire [47:0] c_i9[7:0];
    // Similarly the 1/3 DSPs need an input fed back to the 5/7 chain to be added at an earlier point.
    wire [47:0] c_i5_7[7:0];
        
    // CASCADE CHAINS
    wire [47:0] i15_to_i9[7:0];    
    wire [47:0] i9_to_i11_13[7:0];
    wire [47:0] i11_13_to_i5_7[7:0];
    wire [47:0] i5_7_to_i1_3[7:0];


    // Our first attempt here assumed that we could do a full 2x DSP add so long as everything was input registered.
    // That... doesn't work.
    // Let's assume that in order to do that we need to have the *mults* registered.
    // Luckily we have VERY FEW of these to deal with now.
    // Our "2-clock runs" (no PREG) are
    // BIT 0: i15 -> i9
    // BIT 1: i9 -> i11_13
    // BIT 2: i9 -> i11_13
    // BIT 7: i15 -> i9
    // That's it.      
    //
    // For each of these just strip AREG/DREG back 1 and add MULT_REG and see what happens.
    // i15:
    // AREG = 1 for everyone
    // DREG = 0 for i==0/i==7
    // MULT_REG = 1 for i==0/i==7
    generate
        genvar i;
        
        for (i=0;i<NSAMPS;i=i+1) begin : BIT
            // CREATE THE DELAYS
            reg [11:0] samp_store = {12{1'b0}};
            // we want z^-32: we get z^-8 from store
            // z^-16 from second FF
            // we need z^-16 again, so that's A=1
            wire [11:0] samp_srldelay;
            srlvec #(.NBITS(12)) u_delay(.clk(clk_i),.ce(1'b1),.a(1),.din(samp_store),.dout(samp_srldelay));
            reg [11:0] samp_delay = {12{1'b0}};
            always @(posedge clk_i) begin : DLYS
                samp_store <= xin[i];
                samp_delay <= samp_srldelay;
            end
            assign xin_store[i] = samp_store;
            assign xin_delay[i] = samp_delay;
            
            
            ///////////////////////////////////////////////////
            //                   TAP 15/16                   //
            ///////////////////////////////////////////////////
            
            // i15: i15 = z^-15/z^-17:
            // BIT 0 z^-15/z^-17: xin[1]z^-16 and xin[7]z^-24
            // BIT 1 z^-14/z^-16: xin[2]z^-16 and xin[0]z^-16
            // BIT 2 z^-13/z^-15: xin[3]z^-16 and xin[1]z^-16
            // BIT 3 z^-12/z^-14: xin[4]z^-16 and xin[2]z^-16
            // BIT 4 z^-11/z^-13: xin[5]z^-16 and xin[3]z^-16
            // BIT 5 z^-10/z^-12: xin[6]z^-16 and xin[4]z^-16
            // BIT 6 z^-9/z^-11:  xin[7]z^-16 and xin[5]z^-16
            // BIT 7 z^-8/z^-10:  xin[0]z^-8  and xin[6]z^-16
            // All of these can be directly fed into DSPs.
            // Bit 0 and 7 need AREG=2/DREG=1 to delay the inputs relative to each other.
            // inputs are D=(i+1)%8 and A=(i+7)%8
            // i16: i16 = z^-16
            // BIT 0 z^-16: xin[0]z^-16
            // BIT 1 z^-15: xin[1]z^-16
            // BIT 2 z^-14: xin[2]z^-16
            // BIT 3 z^-13: xin[3]z^-16
            // BIT 4 z^-12: xin[4]z^-16
            // BIT 5 z^-11: xin[5]z^-16
            // BIT 6 z^-10: xin[6]z^-16
            // BIT 7 z^-9 : xin[7]z^-16
            //
            // For bit 0: AREG=2/DREG=1, CREG=1 gives
            // b15*(xin[1]z^-8 + xin[7]z^-16)+b16*xin[0]z^-8
            // For bit 1-6: AREG=1/DREG=1, CREG=1 gives
            // b15*(xin[2->6]z^-8 + xin[0->5]z^-8)+b16*xin[1->6]z^-8
            // Bit 7 is annoying, since we need to store xin[7] to align
            // properly, and we'll be one clock behind everyone else.
            // Everyone else has calculated (i15+i16)z^8.
            // So for bit 7: xin[7]_store => xin[7]z^-8
            // AREG=2/DREG=1/CREG=1 gives
            // b15*(xin[0]z^-8 + xin[6]z^-16) + b16*xin[7]z^-16
            // = (i15 + i16)z^0
            wire [25:0] a_i15;
            wire [25:0] d_i15;
            wire [47:0] c_i15;
            
            assign a_i15 = `QCONV( xin[(i+7)%8] , 12, 0, 17, 9 );
            assign d_i15 = `QCONV( xin[(i+1)%8] , 12, 0, 17, 9 );
            // i16 is (16384/32768) = 0.5, so it's >> 1. So just treat it as a Q11.1 input.
            if (i == 7) begin : B0CT
                assign c_i15 = `QCONV( xin_store[i] , 11, 1, 24, 24 );                
            end else begin : B0C
                assign c_i15 = `QCONV( xin[i], 11, 1, 24, 24 );
            end
            
//            fir_dsp_core #(.AREG( (i==0 || i==7) ? 2 : 1),
            fir_dsp_core #(.AREG(1),
//                           .DREG(1),
                           .DREG( (i==0 || i==7) ? 0 : 1),
                           .MULT_REG( (i==0 || i==7) ? 1 : 0),
                           .CREG(1),
                           .USE_C("TRUE"),
                           .ADD_PCIN("FALSE"),
                           .PREG( (i==0 || i == 7) ? 0 : 1 ))
                u_i15( .clk_i(clk_i),
                       .a_i(a_i15),
                       .b_i(b_coeff15),
                       .d_i(d_i15),
                       .c_i(c_i15),
                       .pcout_o(i15_to_i9[i]));
            // DELAY AFTER TAP 15/16:
            // 0: z^8   (PREG=0)
            // 1: z^0   (PREG=1)
            // 2: z^0   (PREG=1)
            // 3: z^0   (PREG=1)
            // 4: z^0   (PREG=1)
            // 5: z^0   (PREG=1)
            // 6: z^0   (PREG=1)
            // 7: z^0   (PREG=0)

            ///////////////////////////////////////////////////
            //                   TAP 9                       //
            ///////////////////////////////////////////////////
            
            // i9: i9 = z^-9/z^-23:
            // BIT 0 z^-9/z^-23:  xin[7]z^-16 and xin[1]z^-24
            // BIT 1 z^-8/z^-22:  xin[0]z^-8  and xin[2]z^-24
            // BIT 2 z^-7/z^-21:  xin[1]z^-8  and xin[3]z^-24
            // BIT 3 z^-6/z^-20:  xin[2]z^-8  and xin[4]z^-24
            // BIT 4 z^-5/z^-19:  xin[3]z^-8  and xin[5]z^-24
            // BIT 5 z^-4/z^-18:  xin[4]z^-8  and xin[6]z^-24
            // BIT 6 z^-3/z^-17:  xin[5]z^-8  and xin[7]z^-24
            // BIT 7 z^-2/z^-16:  xin[6]z^-8  and xin[0]z^-16
            //
            // bit0/bit7 have the same structure, as do bit1-bit6.
            // Bit0/7: A=xin[1]/xin[0], D=xin[7]/xin[6]. AREG=2/DREG=1 gives
            // B0: (xin[1]z^-16 + xin[7]z^-8) = i9 z^8
            // B7: (xin[0]z^-16 + xin[6]z^-8) = i9 z^0
            // Bit2/6: A=xin2-7_store, D=xin0-5. AREG=2/DREG=1 gives
            // B1-6: (xin[2-7]z^-24 + xin[0-5]z^-8) = i9 z^0
            // Note: this is why for B1-6 i15 DSP has PREG=1, because
            // this puts them at (i15+i16)z^0 as well.
            
            // PREG *must* be set for 0/7 (they had PREG=0 in i15/16).
            // PREG is set for 5/6 to delay them for the next DSP.
            wire [25:0] a_i9;
            wire [25:0] d_i9;
            // c_i9 is globally declared
            if (i == 0 || i == 7) begin : I9_B0_B7
                assign a_i9 = `QCONV( xin[(i+1) % 8], 12, 0, 17, 9);
            end else begin : I9_B2_B6
                assign a_i9 = `QCONV( xin_store[(i+1) % 8], 12, 0, 17, 9);
            end         
            assign d_i9 = `QCONV( xin[(i+7) % 8], 12, 0, 17, 9);
            // The C input for i9 is declared globally to allow it to be used later in the chain.
            // Bits 1 and 2 need AREG=1/DREG=0/MULT_REG=1 to allow the 2 DSP calculation.
            fir_dsp_core #(.AREG((i==1 || i==2) ? 1 : 2),
                           .DREG((i==1 || i==2) ? 0 : 1),
                           .MULT_REG((i==1 || i==2) ? 1 : 0),
                           .CREG((i==3 || i == 4) ? 1 : 0),
                           .USE_C((i==3 || i==4) ? "TRUE" : "FALSE"),
                           .ADD_PCIN("TRUE"),
                           .PREG(i==0 || i >2 ? 1 : 0))
                u_i9( .clk_i(clk_i),
                       .a_i(a_i9),
                       .b_i(b_coeff9),
                       .d_i(d_i9),
                       .c_i(c_i9[i]),
                       .pcin_i( i15_to_i9[i] ),
                       .pcout_o(i9_to_i11_13[i]));
            

            // DELAY AFTER TAP 9:
            // 0: z^0   (PREG=1)
            // 1: z^0   (PREG=0)
            // 2: z^0   (PREG=0)
            // 3: z^-8  (PREG=1)
            // 4: z^-8  (PREG=1)
            // 5: z^-8  (PREG=1)
            // 6: z^-8  (PREG=1)
            // 7: z^-8  (PREG=1)
            
            

            ///////////////////////////////////////////////////
            //                   TAP 11/13                   //
            ///////////////////////////////////////////////////
            // i13: i13 = z^-13/z^-19
            // BIT 0 z^-13/z^-19: xin[3]z^-16 and xin[5]z^-24
            // BIT 1 z^-12/z^-18: xin[4]z^-16 and xin[6]z^-24
            // BIT 2 z^-11/z^-17: xin[5]z^-16 and xin[7]z^-24
            // BIT 3 z^-10/z^-16:                                   xin[6]z^-16 and xin[0]z^-16
            // BIT 4 z^-9/z^-15 :                                   xin[7]z^-16 and xin[1]z^-16
            // BIT 5 z^-8/z^-14 : xin[0]z^-8  and xin[2]z^-16
            // BIT 6 z^-7/z^-13 : xin[1]z^-8  and xin[3]z^-16
            // BIT 7 z^-6/z^-12 : xin[2]z^-8  and xin[4]z^-16
            //
            // i11: i11 = z^-11/z^-21
            // BIT 0 z^-11/z^-21: xin[5]z^-16 and xin[3]z^-24
            // BIT 1 z^-10/z^-20: xin[6]z^-16 and xin[4]z^-24
            // BIT 2 z^-9/z^-19 : xin[7]z^-16 and xin[5]z^-24
            // BIT 3 z^-8/z^-18 :                                   xin[0]z^-8  and xin[6]z^-24
            // BIT 4 z^-7/z^-17 :                                   xin[1]z^-8  and xin[7]z^-24
            // BIT 5 z^-6/z^-16 : xin[2]z^-8  and xin[0]z^-16
            // BIT 6 z^-5/z^-15 : xin[3]z^-8  and xin[1]z^-16
            // BIT 7 z^-4/z^-14 : xin[4]z^-8  and xin[2]z^-16
            //
            // Bit0/2 and 5-7 have the same structure:
            // Bit5-7:
            // i13: (xin[0-2]+xin2-4_store)z^-8 = xin[0-2]z^-8+xin[2-4]z^-16 = i13z^0
            // i11: (xin[2-4]+xin0-2_store)z^-8 = xin[4]z^-8+xin[2]z^-16 = i11z^0
            // AREG=1/DREG=1/CREG=1 gives i13z^-8 and i11z^-8, and 5-7 are at z^-8.
            //
            // Bit0-2:
            // i13: (xin[3-5]+xin5-7_store)z^-8 = xin[3-5]z^-8+xin[5-7]z^-16 = i13z^8
            // i11: (xin[5-7]+xin3-5_store)z^-8 = xin[5-7]z^-8+xin[3-5]z^-16 = i11z^8
            // AREG=1/DREG=1/CREG=1 gives i13z^0 and i11z^0, and we are at z^0.
            //
            // Bit3-4: (at z^-8)
            // 
            // i13 BIT 3 z^-10/z^-16:                                   xin[6]z^-16 and xin[0]z^-16
            // i11 BIT 3 z^-8/z^-18 :                                   xin[0]z^-8  and xin[6]z^-24
            // The delay here makes things awkward, so we compute
            // i13 at z^8 (xin[6]+xin[0])
            // add xin[0] to get xin[0]z^-8 - 2(xin[6]+xin[0])z^-16
            // Put xin_store[6] into A with AREG=2/DREG=0 to give
            // xin[6]z^-24 + xin[0]z^-8 - 2(xin[6]+xin[0])z^-16 (desired at z^0)
            // add PREADD_REG = 1 and we have desired at z^-8.
            // We also need to add (i13 >> 8) at z^-24 here: because i9 has PREG=1,
            // we insert i13 into the C register there: CREG=1 creates (xin[6]+xin[0])z^-16,
            // and PREG=1 creates z^-24.

            if (i < 3 || i > 4) begin : I11_13_NORM
                reg [12:0] i13 = {13{1'b0}};
                wire [13:0] i13_x2 = { i13, 1'b0 };
                reg [12:0] i11 = {13{1'b0}};
                always @(posedge clk_i) begin : PREADD_11_13
                    i13 = {xin[(i+3) %8][11],xin[(i+3) % 8]} + {xin_store[(i+5) % 8][11],xin_store[(i+5) % 8]};
                    i11 = {xin[(i+5) %8][11],xin[(i+5) % 8]} + {xin_store[(i+3) % 8][11],xin_store[(i+3) % 8]};                    
                end
                
                wire [25:0] a_i11_13 = `QCONV( i13_x2, 14, 0, 17, 9);
                wire [25:0] d_i11_13 = `QCONV( i11 , 13, 0, 17, 9);
                // we want to insert i13 << 7 >> 15 = i13 >> 8 so treat as Q5.8
                wire [47:0] c_i11_13 = `QCONV(i13 , 5, 8, 24, 24);                
                // just define this, it's unused
                assign c_i9[i] = {48{1'b0}};
                
                fir_dsp_core #(.AREG(1),.DREG(1),.CREG(1),.PREG(1),
                               .SUBTRACT_A("TRUE"),
                               .USE_C("TRUE"),.ADD_PCIN("TRUE"))
                    u_i11_13( .clk_i(clk_i),
                              .a_i(a_i11_13),
                              .b_i(b_coeff11_13),
                              .c_i(c_i11_13),
                              .d_i(d_i11_13),
                              .pcin_i( i9_to_i11_13[i] ),
                              .pcout_o(i11_13_to_i5_7[i]));
            end else begin
                // Remember what we actually need is i11 - 2i13                
                reg [12:0] i13 = {13{1'b0}};
                // annoyingly needs to be 15 bits: i13 gets upshifted so it's 14 bits and then we add a 12-bit number.
                // sign extension means we need the 15th bit.
                reg [14:0] xin01_minus_i13 = {15{1'b0}};
                always @(posedge clk_i) begin : PREADD
                    // generates (xin[6/7]+xin[0/1])z^-8
                    i13 <= {xin[(i+3)% 8][11],xin[i+3 % 8]} + {xin[(i+5) % 8][11], xin[(i+5) % 8] };
                    // generates (xin[6/7]+xin[0/1])z^-16 + xin[0/1]z^-8
                    xin01_minus_i13 <= { {3{xin[(i+5) % 8][11]}}, xin[(i+5) % 8]} - { i13[12], i13, 1'b0 }  ;
                end
                wire [25:0] a_i11_13 = `QCONV(xin_store[(i+3) % 8], 12, 0, 17, 9);
                wire [25:0] d_i11_13 = `QCONV(xin01_minus_i13, 15, 0, 17, 9);
                // we want to insert i13 << 7 >> 15 = i13 >> 8 so treat as Q5.8
                assign c_i9[i] = `QCONV(i13, 5, 8, 24, 24);
                // PREADD_REG here puts us at z^-8, which is where our input is.
                fir_dsp_core #(.AREG(2),.DREG(0),.CREG(1),.PREG(1),.PREADD_REG(1),
                               .SUBTRACT_A("FALSE"),
                               .USE_C("FALSE"),.ADD_PCIN("TRUE"))
                    u_i11_13( .clk_i(clk_i),
                              .a_i(a_i11_13),
                              .b_i(b_coeff11_13),
                              .d_i(d_i11_13),
                              .pcin_i( i9_to_i11_13[i] ),
                              .pcout_o(i11_13_to_i5_7[i]));
            end
            // DELAY AFTER i11_13
            // 0: z^-8   (PREG=1)
            // 1: z^-8   (PREG=1)
            // 2: z^-8   (PREG=1)
            // 3: z^-16  (PREG=1)    
            // 4: z^-16  (PREG=1)
            // 5: z^-16  (PREG=1)
            // 6: z^-16  (PREG=1)
            // 7: z^-16  (PREG=1)
            
            ///////////////////////////////////////////////////
            //                   TAP 5/7                     //
            ///////////////////////////////////////////////////
            // i7: i7 = z^-7/z^-25
            // BIT 0 z^-7/z^-25: xin[1]z^-8 and xin[7]z^-32
            // BIT 1 z^-6/z^-24: xin[2]z^-8 and xin[0]z^-24
            // BIT 2 z^-5/z^-23: xin[3]z^-8 and xin[1]z^-24
            // BIT 3 z^-4/z^-22:    xin[4]z^-8 and xin[2]z^-24
            // BIT 4 z^-3/z^-21:    xin[5]z^-8 and xin[3]z^-24
            // BIT 5 z^-2/z^-20: xin[6]z^-8 and     xin[4]z^-24
            // BIT 6 z^-1/z^-19: xin[7]z^-8 and     xin[5]z^-24
            // BIT 7 z^-0/z^-18: xin[0]z^-0 and xin[6]z^-24
            //
            // i5: i5 = z^-5/z^-27
            // BIT 0 z^-5/z^-27: xin[3]z^-8 and xin[5]z^-32
            // BIT 1 z^-4/z^-26: xin[4]z^-8 and xin[6]z^-32
            // BIT 2 z^-3/z^-25: xin[5]z^-8 and xin[7]z^-32
            // BIT 3 z^-2/z^-24:    xin[6]z^-8 and xin[0]z^-24
            // BIT 4 z^-1/z^-23:    xin[7]z^-8 and xin[1]z^-24
            // BIT 5 z^-0/z^-22: xin[0]z^-0 and     xin[2]z^-24
            // BIT 6 z^ 1/z^-21: xin[1]z^-0 and     xin[3]z^-24
            // BIT 7 z^ 2/z^-20: xin[2]z^-0 and xin[4]z^-24
            //
            // Bit0/bit7 have the same structure with identical delays and
            // the trick can be pulled recasting the sum.
            // BIT0
            // aincalc = 2xin[7]-xin[5]
            // ainstore = aincalc (2xin[7]-xin[5])z^-16
            // dincalc = 2xin[1]0xin[3] (2xin[1]-xin[3])z^-8
            // AREG=2, DREG=0, PREADD_REG=1 gives
            // b57*(2xin[7]-xin[5])z^-40 + (2xin[1]-xin[3])z^-16 = (i7+i5)z^-8
            // BIT7
            // aincalc = 2xin[6]-xin[4]
            // ainstore = aincalc (2xin[6]-xin[4])z^-16
            // dincalc = 2xin[0]-xin[2] (2xin[0]-xin[2])z^-8
            // AREG=2, DREG=0, PREADD_REG=1 gives
            // b57*(2xin[6]-xin[4])z^-40 + (2xin[0]-xin[2])z^-16 = (i7+i5)z^-16
            //
            // bit1/2 need to add *stores* instead
            // aincalc = (2xin[0]-xin6_store)
            // ainstore = aincalc (2xin[0]z^-16 - xin[6]z^-24)
            // dincalc = 2xin[2]-xin[4] (2xin[2]-xin[4])z^-8
            // AREG=1, DREG=0, PREADD_REG=1 gives
            // b57*(2xin[0]z^-32 - xin[6]z^-40 + 2xin[2]z^-16 - xin[4]z^-16) = (i7+i5)z^-8
            //
            // bit3/4 are similar to bit0/7 but don't need the store
            // aincalc = 2xin[2]-xin[0] (2xin[2]-xin[0])z^-8
            // dincalc = 2xin[4]-xin[6] (2xin[4]-xin[6])z^-8
            // AREG=2, DREG=0, PREADD_REG=1 gives
            // b57*((2xin[2]-xin[0])z^-32 + (2xin[4]-xin[6])z^-16) = (i7+i5)z^-8
            // MULT_REG=1 gives (i7+i5)z^-16.
            //
            // bit5/6:
            // aincalc = (2xin4-5_store - xin2-3_store) (z^-16)
            // dincalc = (2xin6-7_store - xin[0-1]) (2xin[6-7]z^-16 - xin[0-1]z^-8)
            // AREG=2, DREG=0, PREADD_REG=1 gives
            // b57*((2xin[4-5] - xin[2-3])z^-40 + 2xin[6-7]z^-24 - xin[0-1]z^-16) = (i7+i5)z^-16            
            
            // Everyone works the same, although not everyone uses the store.
            // N.B. I ACTUALLY KNOW OF ULTRASLEAZE WAYS TO GET RID OF AINSTORE HERE
            // CONSIDER THIS FOR THE FUTURE
            reg [13:0] aincalc = {14{1'b0}};
            reg [13:0] dincalc = {14{1'b0}};
            
            wire [25:0] a_i5_7;
            wire [25:0] d_i5_7;
                        
            if (i==0 || i == 7) begin : I5_7_07
                // AREG 2, DREG 0, PREADD_REG = 1
                reg [13:0] ainstore = {14{1'b0}};
                always @(posedge clk_i) begin : I5_7_07_PREADD
                    aincalc <= `DLYFF { xin[(i+7) % 8][11], xin[(i+7) % 8], 1'b0 } -
                                         { {2{xin[(i+5) % 8][11]}}, xin[(i+5) % 8] };
                    dincalc <= `DLYFF { xin[(i+1) % 8][11], xin[(i+1) % 8], 1'b0 } -
                                         { {2{xin[(i+3) % 8][11]}}, xin[(i+3) % 8] };
                    ainstore <= aincalc;                                         
                end
                assign a_i5_7 = `QCONV(ainstore, 14, 0, 17, 9);
                assign d_i5_7 = `QCONV(dincalc, 14, 0, 17, 9);
            end else if (i == 1 || i == 2) begin : I5_7_12
                // AREG 1, DREG 0, PREADD_REG = 1
                reg [13:0] ainstore = {14{1'b0}};
                always @(posedge clk_i) begin : I5_7_12_PREADD
                    aincalc <= `DLYFF { xin[(i+7) % 8][11], xin[(i+7) % 8], 1'b0 } -
                                      { {2{xin_store[(i+5) % 8][11]}}, xin_store[(i+5) % 8] };
                    dincalc <= `DLYFF { xin[(i+1) % 8][11], xin[(i+1) % 8], 1'b0 } -
                                        { {2{xin[(i+3) % 8][11]}}, xin[(i+3) % 8] };
                    ainstore <= aincalc;
                end
                assign a_i5_7 = `QCONV(ainstore, 14, 0, 17, 9);
                assign d_i5_7 = `QCONV(dincalc, 14, 0, 17, 9);
            end else if (i == 3 || i == 4) begin : I5_7_34
                // AREG 2, DREG 0, PREADD_REG 1, MULT_REG 1
                // 3/4 don't need the store.
                always @(posedge clk_i) begin : I5_7_34_PREADD
                    aincalc <= `DLYFF { xin[(i+7) % 8][11], xin[(i+7) % 8], 1'b0 } -
                                         { {2{xin[(i+5) % 8][11]}}, xin[(i+5) % 8] };
                    dincalc <= `DLYFF { xin[(i+1) % 8][11], xin[(i+1) % 8], 1'b0 } -
                                         { {2{xin[(i+3) % 8][11]}}, xin[(i+3) % 8] };                
                end
                assign a_i5_7 = `QCONV(aincalc, 14, 0, 17, 9);
                assign d_i5_7 = `QCONV(dincalc, 14, 0, 17, 9);
            end else if (i == 5 || i == 6) begin : I5_7_56
                // AREG 2, DREG 0, PREADD_REG 1
                // and 5/6 don't need the store, but do need to work with stores as inputs
                always @(posedge clk_i) begin : I5_7_56_PREADD
                    aincalc <= `DLYFF { xin_store[(i+7) % 8][11], xin_store[(i+7) % 8], 1'b0 } -
                                      { {2{xin_store[(i+5) % 8][11]}}, xin_store[(i+5) % 8] };
                    dincalc <= `DLYFF { xin_store[(i+1) % 8][11], xin_store[(i+1) % 8], 1'b0 } -
                                        { {2{xin[(i+3) % 8][11]}}, xin[(i+3) % 8] };
                end
                assign a_i5_7 = `QCONV(aincalc, 14, 0, 17, 9);
                assign d_i5_7 = `QCONV(dincalc, 14, 0, 17, 9);
            end

            fir_dsp_core #( .AREG( (i == 1 || i == 2) ? 1 : 2 ),
                            .DREG(0),
                            .PREADD_REG(1),
                            .MULT_REG( (i == 3 || i == 4) ? 1 : 0 ),
                            .PREG(1),
                            .USE_C((i==3 || i == 4) ? "TRUE" : "FALSE"),
                            .ADD_PCIN("TRUE"))
                u_i5_7( .clk_i(clk_i),
                        .a_i(a_i5_7),
                        .b_i(b_coeff5_7),
                        .c_i(c_i5_7[i]),
                        .d_i(d_i5_7),
                        .pcin_i( i11_13_to_i5_7[i] ),
                        .pcout_o( i5_7_to_i1_3[i] ));
                                    
            // DELAY AFTER i5_7
            // 0: z^-16  (PREG=1)
            // 1: z^-16  (PREG=1)
            // 2: z^-16  (PREG=1)
            // 3: z^-24  (PREG=1)
            // 4: z^-24  (PREG=1)
            // 5: z^-24  (PREG=1)
            // 6: z^-24  (PREG=1)
            // 7: z^-24  (PREG=1)            

            ///////////////////////////////////////////////////
            //                   TAP 1/3                     //
            ///////////////////////////////////////////////////
            
            // These taps require the farthest reach back,
            // and so we just create a delay output for these.
            // 
            // i3: i3 = z^-3/z^-29
            // BIT 0 z^-3/z^-29: xin[5]z^-8 and xin[3]z^-32
            // BIT 1 z^-2/z^-28: xin[6]z^-8 and xin[4]z^-32
            // BIT 2 z^-1/z^-27: xin[7]z^-8 and xin[5]z^-32
            // BIT 3 z^-0/z^-26:    xin[0]z^ 0 and xin[6]z^-32
            // BIT 4 z^ 1/z^-25:    xin[1]z^ 0 and xin[7]z^-32
            // BIT 5 z^ 2/z^-24: xin[2]z^ 0 and xin[0]z^-24
            // BIT 6 z^ 3/z^-23: xin[3]z^ 0 and xin[1]z^-24
            // BIT 7 z^ 4/z^-22: xin[4]z^ 0 and xin[2]z^-24
            //
            // i1: i1 = z^-1/z^-31
            // BIT 0 z^-1/z^-31: xin[7]z^-8 and xin[1]z^-32
            // BIT 1 z^ 0/z^-30: xin[0]z^-0 and xin[2]z^-32
            // BIT 2 z^ 1/z^-29: xin[1]z^-0 and xin[3]z^-32
            // BIT 3 z^ 2/z^-28:    xin[2]z^ 0 and xin[4]z^-32
            // BIT 4 z^ 3/z^-27:    xin[3]z^ 0 and xin[5]z^-32
            // BIT 5 z^ 4/z^-26:    xin[4]z^ 0 and xin[6]z^-32
            // BIT 6 z^ 5/z^-25:    xin[5]z^ 0 and xin[7]z^-32
            // BIT 7 z^ 6/z^-24: xin[6]z^ 0 and xin[0]z^-24
            //
            // bit0/7:
            // Then we do (xin5_store+xin3_delay) = i3 z^-8 (=xin[5]z^-16 + xin[3]z^-40)
            //            (xin7_store+xin1_delay) = i1 z^-8 (=xin[7]z^-16 + xin[3]z^-40)
            // AREG=1/DREG=1/CREG=1 and we're at z^-16: so put PREG=1 on the prior for bit 0 and you're done
            
            // bit 1/2:
            // do (xin[6-7]_store+xin4-5_delay) = i3 z^-8 (=xin[6-7]z^-16 + xin[4-5]z^-40)
            // do (xin[0-1] + xin2-3_delay)     = i1 z^-8 (=xin[0-1]z^-8 + xin[2-3]z^-40)
            // AREG=1/DREG=1/CREG=1 and we're at z^-16, again put PREG=1 on the prior and you're done
            //
            // bit 3/4 are at z^-24 because it saves us a delay afterwards. We generate this by
            // adding an extra delay (MULT_REG = 1), setting PREG = 1 before, and feeding *our*
            // i3 into i5_7 instead, where it becomes z^-16 at a z^-16 add step.
            //
            // BIT 3 z^-0/z^-26: xin[0]z^ 0 and xin[6]z^-32
            // BIT 3 z^ 2/z^-28: xin[2]z^ 0 and xin[4]z^-32
            // do xin[0:1] + xin[6:7]_delay = i3 z^-8 (=xin[0-1]z^-8 + xin[6-7]z^-40)
            // do xin[2:3] + xin[4:5]_delay = i1 z^-8 (=xin[2-3]z^-8 + xin[4-5]z^-40)
            // AREG=1/DREG=1/MULT_REG=1 and we're at z^-24.

            // bit 5-7 are now at z^-24.
                        
            // bit 5/6:
            // do (xin_store[2-3] + xin[0-1]_delay) = i3 z^-16 (=xin[2-3]z^-16 + xin[0-1]z^-40)
            // do (xin[4-5] + xin[6-7]_delay) = i1 z^-8  (=xin[4-5]z^-8 + xin[6-7]z^-40)
            // AREG=2/DREG=1/CREG=1 and we're at z^-24.
            //
            // bit 7:
            // do (xin_store[4] + xin_delay[2]) = i3 z^-16 = (xin[4]z^-16 + xin[2]z^-40)
            // do (xin_store[6] + xin_delay[0]) = i1 z^-16 = (xin[6]z^-16 + xin[0]z^-40)
            // AREG=1/DREG=1/CREG=1 and we're at z^-24 like we want.
            //            
            reg [12:0] i3 = {13{1'b0}};
            reg [12:0] i1 = {13{1'b0}};
            // i1 goes into A because for bit5/6 it needs to be delayed an extra clock.
            wire [25:0] a_i1_3 = `QCONV(i1, 13, 0, 17, 9);
            wire [25:0] d_i1_3 = `QCONV(i3, 13, 0, 17, 9);
            // These are both actually downshift by 8, so we go from Q13.0 to Q5.8
            wire [47:0] c_i1_3 = (i==3 || i == 4) ? {48{1'b0}} : `QCONV(i3, 5, 8, 24, 24);
            assign c_i5_7[i] = (i==3 || i == 4) ? `QCONV(i3, 5, 8, 24, 24) : {48{1'b0}};
            
            if (i==0 || i==7) begin : I1_3_07
                // 0/7 add store/delay and store/delay
            // Then we do (xin5_store+xin3_delay) = i3 z^-8 (=xin[5]z^-16 + xin[3]z^-40)
            //            (xin7_store+xin1_delay) = i1 z^-8 (=xin[7]z^-16 + xin[3]z^-40)
                always @(posedge clk_i) begin : I1_3_07_PREADD
                    i3 <= {xin_store[(i+5) % 8][11],xin_store[(i+5) % 8]} +
                          {xin_delay[(i+3) % 8][11],xin_delay[(i+3) % 8]};
                    i1 <= {xin_store[(i+7) % 8][11],xin_store[(i+7) % 8]} +
                          {xin_delay[(i+1) % 8][11],xin_delay[(i+1) % 8]};
                end
            end else if (i== 1 || i == 2 || i == 5 || i == 6) begin : I1_3_12
                // 1/2 and 5/6 add store/delay and xin/delay
                always @(posedge clk_i) begin : I1_3_07_PREADD
                    i3 <= {xin_store[(i+5) % 8][11],xin_store[(i+5) % 8]} +
                          {xin_delay[(i+3) % 8][11],xin_delay[(i+3) % 8]};
                    i1 <= {xin[(i+7) % 8][11],xin[(i+7) % 8]} +
                          {xin_delay[(i+1) % 8][11],xin_delay[(i+1) % 8]};
                end                
            end else if (i== 3 || i == 4) begin : I1_3_34
                // 3/4 add xin/delay and xin/delay
                always @(posedge clk_i) begin : I1_3_07_PREADD
                    i3 <= {xin[(i+5) % 8][11],xin[(i+5) % 8]} +
                          {xin_delay[(i+3) % 8][11],xin_delay[(i+3) % 8]};
                    i1 <= {xin[(i+7) % 8][11],xin[(i+7) % 8]} +
                          {xin_delay[(i+1) % 8][11],xin_delay[(i+1) % 8]};
                end                
            end
            
            wire [47:0] i1_3_out;
            
            // Parameters
            // bit0: AREG 1 DREG 1 CREG 1 MULT_REG 0
            // bit1: AREG 1 DREG 1 CREG 1 MULT_REG 0
            // bit2: AREG 1 DREG 1 CREG 1 MULT_REG 0
            // bit3: AREG 1 DREG 1 MULT_REG 1
            // bit4: AREG 1 DREG 1 MULT_REG 1
            // bit5: AREG 2 DREG 1 CREG 1 MULT_REG 0
            // bit6: AREG 2 DREG 1 CREG 1 MULT_REG 0
            // bit7: AREG 1 DREG 1 CREG 1 MULT_REG 0
            
            // we do NOT subtract A for DSP1/3
            // We're multiplying by -23, and then adding 128 for i3 to get 105.
            fir_dsp_core #(.ADD_PCIN("TRUE"),
                           .SUBTRACT_A("FALSE"),
                           .AREG( (i==5 || i==6) ? 2 : 1),
                           .DREG(1),
                           .CREG(1),
                           .PREG(1),
                           .MULT_REG( (i==3 || i==4) ? 1 : 0),
                           .USE_C( (i==3 || i==4) ? "FALSE" : "TRUE"))
                u_i1_3( .clk_i(clk_i),
                        .a_i(a_i1_3),
                        .b_i(b_coeff1_3),
                        .d_i(d_i1_3),
                        .c_i(c_i1_3),
                        .pcin_i( i5_7_to_i1_3[i] ),
                        .p_o( i1_3_out ));        
            // DELAY AFTER i5_7
            // 0: z^-16  (PREG=1)
            // 1: z^-16  (PREG=1)
            // 2: z^-16  (PREG=1)
            // 3: z^-24  (PREG=1)
            // 4: z^-24  (PREG=1)
            // 5: z^-24  (PREG=1)
            // 6: z^-24  (PREG=1)
            // 7: z^-24  (PREG=1)            
            if (i < 3) begin : ADD_DELAY
                reg [OUTQ_INT+OUTQ_FRAC-1:0] out_delay = {(OUTQ_INT+OUTQ_FRAC){1'b0}};
                always @(posedge clk_i) begin : ADD_DELAY_LOGIC
                    // NOTE NOTE NOTE NOTE NOTE NOTE NOTE
                    // I SHOULD PROBABLY DEAL WITH UNDERFLOW/OVERFLOW HERE
                    out_delay = i1_3_out[ (24-OUTQ_FRAC) +: (OUTQ_INT+OUTQ_FRAC) ];
                end
                assign out_o[(OUTQ_INT+OUTQ_FRAC)*i +: (OUTQ_INT+OUTQ_FRAC)] = out_delay;
            end else begin : NODELAY
                assign out_o[(OUTQ_INT+OUTQ_FRAC)*i +: (OUTQ_INT+OUTQ_FRAC)] = i1_3_out[ (24-OUTQ_FRAC) +: (OUTQ_INT+OUTQ_FRAC)];
            end
        end
    endgenerate
            
endmodule
