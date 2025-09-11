`timescale 1ns / 1ps

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

// Second version of a Shannon-Whitaker LP filter.
//
// This version ensures that all DSPs have at least a preadd or multiplier
// register in their path, which should guarantee timing even when the
// FPGA becomes extremely full.
module shannon_whitaker_lpfull_v2 #(parameter NBITS=12,
                                    parameter NSAMPS=8,
                                    parameter OUTQ_INT=12,
                                    parameter OUTQ_FRAC=0)(
        input clk_i,
        input [NBITS*NSAMPS-1:0] in_i,
        output [(OUTQ_INT+OUTQ_FRAC)*NSAMPS-1:0] out_o
    );
    
    // coefficient definitions
    // NOTE: these are in Q3.15 format, so divide by 32768.
    //       In documentation this is described as Q0.15 but expanding to Q3.15 is automatic in definition.
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

    // Coefficients are Q3.15 (18 bits)
    // Inputs are Q17.9 (26 bits).
    // -- Q17.9 allows a *ton* of pre-adds of a 12-bit number
    //    before insertion.
    // Preadder expands to 27 bits (Q18.9)
    // Results in Q21.24, which ends up as Q24.24
    localparam MULT_INT = 17;
    localparam MULT_FRAC = 9;
    localparam ADD_INT = 24;
    localparam ADD_FRAC = 24;
    
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

    // Convert between fixed point representations (this only works to EXPAND, not COMPRESS)
    // n.b. I should convert this into a function: the macro version apparently causes problems when passed with parameters.
    // Who knows, Xilinx weirdness.
    `define QCONV( inval , SRC_QINT, SRC_QFRAC, DST_QINT, DST_QFRAC )   \
        ( { {( DST_QINT - SRC_QINT ) { inval[ (SRC_QINT+SRC_QFRAC) - 1 ] }}, inval, { ( DST_QFRAC - SRC_QFRAC ) {1'b0} } } )


    // We generate 2 delayed inputs.
    wire [NBITS-1:0] xin_store[NSAMPS-1:0];      // these are at z^-8
    wire [NBITS-1:0] xin_delay[NSAMPS-1:0];      // these are at z^-32        
    // actual outputs
    wire [47:0] sample_out[NSAMPS-1:0];
    generate
        genvar i;
        for (i=0;i<NSAMPS;i=i+1) begin : DLY
            // Generate the delays.
            reg [NBITS-1:0] samp_store = {NBITS{1'b0}};
            reg [NBITS-1:0] samp_delay = {NBITS{1'b0}};
            wire [NBITS-1:0] samp_srldelay;
            // we want z^-32: we get z^-8 from store
            // z^-16 from second FF
            // we need z^-16 again, so that's A=1
            srlvec #(.NBITS(NBITS)) u_delay(.clk(clk_i),.ce(1'b1),.a(1),.din(samp_store),.dout(samp_srldelay));
            always @(posedge clk_i) begin : DLYFF
                samp_store <= xin[i];
                samp_delay <= samp_srldelay;
            end
            assign xin_store[i] = samp_store;
            assign xin_delay[i] = samp_delay;
            // Now we generate the FIR loops.
            // There are 3 overall structures: 0-2, 3-4, and 5-7.
            // However, 3 and 4 are identical except for i11/13.
            if (i<5) begin : STRUCT0
                // Structure 0 cascades.
                wire [47:0] i11_13_to_i5_7;
                wire [47:0] i5_7_to_i1_3;
                wire [47:0] i1_3_to_i15;
                wire [47:0] i15_to_i9;
                wire [29:0] i15_to_i9_acin;
                
                ///////////////////////////////////
                //             TAP 11/13         //
                ///////////////////////////////////
                
                if (i < 3) begin : STRUCT0A
                    // compute A13/A11 first.
                    reg [NBITS:0] A13 = {NBITS+1{1'b0}};
                    // generate 2*A13
                    wire [NBITS+1:0] A13x2 = { A13, 1'b0 };
                    reg [NBITS:0] A11 = {NBITS+1{1'b0}};
                    always @(posedge clk_i) begin : PREADD_11_13
                        // sign extend and add
                        A13 <= { xin[i+3][NBITS-1], xin[i+3] } +
                               { xin_store[i+5][NBITS-1], xin_store[i+5] };
                        // sign extend and add
                      A11 <= { xin_store[i+3][NBITS-1], xin_store[i+3] } +
                      { xin[i+5][NBITS-1], xin[i+5] };
                    end
                    // AD/C/PREG=1
                    // A/D/MREG=0
                    // (z^(i+3)+z^(i+5)z^-8)(z^-8)(z^-8) = (z^i)(z^-13 + z^-19)
                    //                       reg  preadd
                    // (z^(i+3)z^-8+z^(i+5))(z^-8)(z^-8) = (z^i)(z^-11 + z^-21)
                    //                       reg  preadd
                    fir_dsp_core #(.AREG(0),.DREG(0),.MULT_REG(0),
                                   .PREADD_REG(1),.CREG(1),.PREG(1),
                                   .ADD_PCIN("FALSE"),
                                   .USE_C("TRUE"),
                                   .SUBTRACT_A("TRUE"))
                        u_i11_13( .clk_i(clk_i),
                                  .a_i(`QCONV( A13x2, 14, 0, 17, 9)),
                                  .d_i(`QCONV( A11, 13, 0, 17, 9 )),
                                  .b_i( b_coeff11_13 ),
                                  // We want (A13 * 2^7 * 2^-15) = (A13 * 2^-8)
                                  .c_i(`QCONV( A13, 5, 8, 24, 24 )),
                                  .pcout_o( i11_13_to_i5_7 ));
                end else begin : STRUCT0B
                    // A13 computation...
                    reg [NBITS:0] A13 = {NBITS+1{1'b0}};
                    // 2A13
                    wire [NBITS+1:0] A13_x2 = { A13, 1'b0 };
                    // -2A13 plus x[i-3]
                    reg [NBITS+2:0] x_minus_A13_x2 = {NBITS+3{1'b0}};
                    //  and A13_store
                    reg [NBITS:0] A13_store = {NBITS+1{1'b0}};
                    
                    always @(posedge clk_i) begin : PREADD_11_13
                        A13 <= { xin[i+3][NBITS-1], xin[i+3] } +
                               { xin[i-3][NBITS-1], xin[i-3] };
                        A13_store <= A13;
                        // need to sign extend 3 bits and 1 bits respectively
                        x_minus_A13_x2 <= { {3{xin[i-3][NBITS-1] }}, xin[i-3] } -
                                          { A13_x2[NBITS+1], A13_x2};
                    end
                    // AREG=2
                    // M/CREG=1
                    // AD/D/PREG=0
                    fir_dsp_core #(.AREG(2),
                                   .MULT_REG(1),.CREG(1),
                                   .DREG(0),.PREADD_REG(0),.PREG(0),
                                   .ADD_PCIN("FALSE"),
                                   .USE_C("TRUE"),
                                   .SUBTRACT_A("FALSE"))
                        u_i11_13( .clk_i(clk_i),
                                  .a_i(`QCONV( xin_store[i+3], 12, 0, 17, 9)),
                                  .d_i(`QCONV( x_minus_A13_x2, 15, 0, 17, 9)),
                                  .b_i( b_coeff11_13 ),
                                  // We want (A13 * 2^7 * 2^-15) = (A13 * 2^-8)
                                  .c_i(`QCONV( A13_store, 5, 8, 24, 24 )),
                                  .pcout_o( i11_13_to_i5_7 ));                  
                    
                end                                                       
                ///////////////////////////////////
                //             TAP 5/7           //
                ///////////////////////////////////
                
                // merge the short-delay samples. Sign extend first                
                wire [NBITS+1:0] A_short_in0_x2 = { {xin[i+1][NBITS-1]}, xin[i+1], 1'b0 };
                wire [NBITS+1:0] A_short_in1 =    { {2{ xin[i+3][NBITS-1]}}, xin[i+3] };
                reg [NBITS+1:0] A_short = {NBITS+2{1'b0}};
                // merge the long-delay samples. Sign extend first
                wire [NBITS+1:0] A_long_in0_x2 = (i == 0) ?
                    { xin_store[i+7][NBITS-1], xin_store[i+7], 1'b0 } :
                    { xin[i-1][NBITS-1], xin[i-1], 1'b0 };
                wire [NBITS+1:0] A_long_in1 = ( i < 3 ) ?                
                    { {2{ xin_store[i+5][NBITS-1]}}, xin_store[i+5] } :
                    { {2{ xin[i-3][NBITS-1]}}, xin[i-3] };
                reg [NBITS+1:0] A_long = {NBITS+2{1'b0}};
                
                always @(posedge clk_i) begin : PREADD_5_7
                    A_short <= A_short_in0_x2 - A_short_in1;
                    A_long <= A_long_in0_x2 - A_long_in1;
                end
                
                // AREG=2
                // AD/PREG = 1
                // D/MREG = 0
                fir_dsp_core #(.AREG(2),.PREADD_REG(1),.PREG(1),
                               .DREG(0),.MULT_REG(0),
                               .ADD_PCIN("TRUE"),
                               .USE_C("FALSE"),
                               .SUBTRACT_A("FALSE"))
                    u_i5_7( .clk_i(clk_i),
                           .a_i( `QCONV( A_long , 13, 0, 17, 9) ),
                           .d_i( `QCONV( A_short, 13, 0, 17, 9) ),
                           .b_i( b_coeff5_7 ),
                           .pcin_i( i11_13_to_i5_7 ),
                           .pcout_o( i5_7_to_i1_3 ));
                
                ///////////////////////////////////
                //             TAP 1/3           //
                ///////////////////////////////////
                
                // construct A3
                reg [NBITS:0] A3 = {NBITS+1{1'b0}};
                // construct A1
                reg [NBITS:0] A1 = {NBITS+1{1'b0}};
                
                // A1 is made from
                // 0:   xin_store[i+7] + xin_delay[i+1]
                // 1-4: xin[i-1] + xin_delay[i+1]
                wire [NBITS-1:0] A1_in0 = (i == 0) ? xin_store[i+7] : xin[i-1];
                wire [NBITS-1:0] A1_in1 = xin_delay[i+1];
                // A3 is made from
                // 0-2: xin_store[i+5] + xin_delay[i+3]
                // 4-5: xin[i-3] + xin_delay[i+3]
                wire [NBITS-1:0] A3_in0 = (i < 3) ? xin_store[i+5] : xin[i-3];
                wire [NBITS-1:0] A3_in1 = xin_delay[i+3];
                
                always @(posedge clk_i) begin : PREADD_1_3
                    A1 <= { A1_in0[NBITS-1], A1_in0 } +
                          { A1_in1[NBITS-1], A1_in1 };
                    A3 <= { A3_in0[NBITS-1], A3_in0 } +
                          { A3_in1[NBITS-1], A3_in1 };
                end
                // M/CREG = 1
                // A/D/AD/PREG=0
                // Multiplier gets preferenced over preadder because of the chain up to
                // i5/7
                fir_dsp_core #(.MULT_REG(1),.CREG(1),
                               .AREG(0),.DREG(0),.PREADD_REG(0),.PREG(0),
                               .ADD_PCIN("TRUE"),
                               .USE_C("TRUE"),
                               .SUBTRACT_A("FALSE"))
                    u_i1_3( .clk_i(clk_i),
                           .a_i(`QCONV(A3, 13, 0, 17, 9) ),
                           .d_i(`QCONV(A1, 13, 0, 17, 9) ),
                           .b_i(b_coeff1_3),
                           // we want (A3 << 7) >> 15 = A3 >> 8
                           .c_i(`QCONV(A3, 5, 8, 24, 24)),
                           .pcin_i( i5_7_to_i1_3 ),
                           .pcout_o( i1_3_to_i15 ));
                
                ///////////////////////////////////
                //             TAP 15/9          //
                ///////////////////////////////////
                
                // Taps 15/9 cascade one input.
                // For sample 0, the i15 inputs are A: xin_store[i+7] and D: xin_store[i+1]
                // sample 1-4 have A: xin[i-1] and D: xin_store[i+1]
                // i9 A input is cascade
                // i9 D input is xin_delay[i+1]
                // i9 C input is xin_delay[i]
                
                wire [11:0] Ain_i15 = (i == 0) ? xin_store[i+7] : xin[i-1];
                
                // AREG/ACASCREG=2
                // AD/D/M/PREG=1
                fir_dsp_core #(.USE_ACOUT("TRUE"),
                               .AREG(2),.ACASCREG(2),
                               .DREG(1),.PREADD_REG(1),.MULT_REG(1),.PREG(1),
                               .ADD_PCIN("TRUE"),
                               .USE_C("FALSE"))
                    u_i15( .clk_i(clk_i),
                           .a_i(`QCONV(Ain_i15, 12, 0, 17, 9)),
                           .d_i(`QCONV(xin_store[i+1], 12, 0, 17, 9)),
                           .b_i(b_coeff15),
                           .acout_o( i15_to_i9_acin ),
                           .pcin_i( i1_3_to_i15 ),
                           .pcout_o( i15_to_i9 ));                
                fir_dsp_core #(.USE_ACIN("TRUE"),
                               .AREG(1),.DREG(1),.CREG(1),.MULT_REG(1),.PREG(1),
                               .PREADD_REG(0),
                               .ADD_PCIN("TRUE"),
                               .USE_C("TRUE"))
                    u_i9( .clk_i(clk_i),
                          .acin_i( i15_to_i9_acin),
                          .d_i(`QCONV(xin_delay[i+1], 12, 0, 17, 9)),
                          .b_i(b_coeff9),
                          // we want xin_delay[i] << 14 >> 15 = >> 1
                          .c_i(`QCONV(xin_delay[i], 11, 1, 24, 24)),
                          .pcin_i( i15_to_i9 ),
                          .p_o( sample_out[i] ));
                  
            end else begin : STRUCT1
                // structure 1
                wire [47:0] i9_to_i15;
                wire [29:0] i9_to_i15_acin;
                wire [47:0] i15_to_i11_13;
                wire [47:0] i11_13_to_i1_3;
                wire [47:0] i1_3_to_i5_7;
                // structure 1 also feeds back A13 to i9 so we declare the C input early.
                wire [47:0] Cin_i9;                
                
                ///////////////////////////////////
                //             TAP 9/15          //
                ///////////////////////////////////
                
                // Taps 9/15 cascade one input.
                // For sample 5-6, the i9 inputs are A: xin_store[i+1] and D: xin[i-1]
                // sample 7 has A: xin[i-7] and D: xin[i-1]
                // i15 A input is cascade
                // i15 D input is xin_store[i-1]
                
                wire [11:0] Ain_i9 = (i == 7) ? xin[i-7] : xin_store[i+1];
                
                // AREG=2
                // ACASCREG/C/D/M/PREG=1
                // ADREG=0
                fir_dsp_core #(.USE_ACOUT("TRUE"),
                               .AREG(2),.ACASCREG(1),.DREG(1),.MULT_REG(1),.PREG(1),
                               .PREADD_REG(0),
                               .USE_C("TRUE"))
                     u_i9( .clk_i(clk_i),
                           .a_i(`QCONV(Ain_i9, 12, 0, 17, 9)),
                           .d_i(`QCONV(xin[i-1], 12, 0, 17, 9)),
                           .b_i(b_coeff9),
                           .c_i(Cin_i9),
                           .acout_o( i9_to_i15_acin ),
                           .pcout_o( i9_to_i15 ));                
                // AD/D/M/PREG=1
                // AREG=0
                fir_dsp_core #(.USE_ACIN("TRUE"),
                               .PREADD_REG(1),.DREG(1),.CREG(1),.MULT_REG(1),.PREG(1),
                               .AREG(0),                               
                               .ADD_PCIN("TRUE"),
                               .USE_C("FALSE"))
                    u_i15(.clk_i(clk_i),
                          .acin_i( i9_to_i15_acin ),
                          .d_i(`QCONV(xin_store[i-1], 12, 0, 17, 9)),
                          .b_i(b_coeff15),
                          .pcin_i( i9_to_i15 ),
                          .pcout_o( i15_to_i11_13 ));

                ///////////////////////////////////
                //             TAP 11/13         //
                ///////////////////////////////////
                
                // compute A13/A11 first.
                reg [NBITS:0] A13 = {NBITS+1{1'b0}};
                // generate 2*A13
                wire [NBITS+1:0] A13x2 = { A13, 1'b0 };
                reg [NBITS:0] A11 = {NBITS+1{1'b0}};
            
                // A13 inputs are xin[i-5] and xin_store[i-3]
                // A11 inputs are xin_store[i-5] and xin[i-3]
                always @(posedge clk_i) begin : PREADD_11_13
                    A13 <= { xin[i-5][NBITS-1], xin[i-5] } +
                           { xin_store[i-3][NBITS-1], xin_store[i-3] };
                    A11 <= { xin_store[i-5][NBITS-1], xin_store[i-5] } +
                           { xin[i-3][NBITS-1], xin[i-3] };
                end
                // add A13 back at i9
                assign Cin_i9 = `QCONV(A13, 5, 8, 24, 24);
                
                // A/C/D/AD/MREG=1
                // PREG=0
                // Our CREG adds tap 16.
                fir_dsp_core #(.AREG(1),.CREG(1),.DREG(1),.PREADD_REG(1),.MULT_REG(1),
                               .PREG(0),
                               .USE_C("TRUE"),
                               .ADD_PCIN("TRUE"),
                               .SUBTRACT_A("TRUE"))
                    u_i11_13( .clk_i(clk_i),
                              .a_i(`QCONV(A13x2, 14, 0, 17, 9)),
                              .d_i(`QCONV(A11, 13, 0, 17, 9)),
                              .b_i(b_coeff11_13),
                              // we want (xin_delay << 14 >> 15 = >> 1)
                              .c_i(`QCONV(xin_delay[i], 11, 1, 24, 24)),
                              .pcin_i(i15_to_i11_13),
                              .pcout_o(i11_13_to_i1_3));

                ///////////////////////////////////
                //             TAP 1/3           //
                ///////////////////////////////////

                // construct A3
                reg [NBITS:0] A3 = {NBITS+1{1'b0}};
                // construct A1
                reg [NBITS:0] A1 = {NBITS+1{1'b0}};

                // A1 is made of
                // 5/6 xin[i-1] xin_delay[i+1]
                // 7   xin_store[i-1] xin_delay[i-7]
                // A3 is made of
                // xin_store[i-3] xin_delay[i-5]
                
                // These are NBITS length! They're sign extended!
                wire [NBITS:0] A1_in0 = (i == 7) ?
                    { xin_store[i-1][NBITS-1], xin_store[i-1] } :
                    { xin[i-1][NBITS-1], xin[i-1] };
                wire [NBITS:0] A1_in1 =
                    { xin_delay[(i+1)%8][NBITS-1], xin_delay[(i+1)%8] };

                always @(posedge clk_i) begin : PREADD_1_3
                    A1 <= A1_in0 + A1_in1;
                    A3 <= { xin_store[i-3][NBITS-1], xin_store[i-3] } +
                          { xin_delay[i-5][NBITS-1], xin_delay[i-5] };                          
                end
                // 5-6 have AREG=1, 7 has AREG=0
                // AD/C/PREG=1
                // D/MREG=0
                fir_dsp_core #(.AREG(i==7 ? 0 : 1),
                               .PREADD_REG(1),.CREG(1),.PREG(1),
                               .DREG(0),.MULT_REG(0),
                               .USE_C("TRUE"),
                               .ADD_PCIN("TRUE"))
                    u_i1_3( .clk_i(clk_i),
                            .a_i(`QCONV(A1, 13, 0, 17, 9)),
                            .d_i(`QCONV(A3, 13, 0, 17, 9)),
                            .b_i(b_coeff1_3),
                            // want (A3 << 7 >> 15 = A3 >> 8)
                            .c_i(`QCONV(A3, 5, 8, 24, 24)),
                            .pcin_i( i11_13_to_i1_3 ),
                            .pcout_o( i1_3_to_i5_7 ) );

                ///////////////////////////////////
                //             TAP 5/7           //
                ///////////////////////////////////
                
                // merge the short-delay samples. Sign extend first                
                // Short delays are
                // 5-6: xin_store[i+1], xin[i-5]
                // 7: xin[i-7], xin[i-5]
                wire [NBITS+1:0] A_short_in0_x2 = (i == 7) ? 
                    { {xin[i-7][NBITS-1]}, xin[i-7], 1'b0 } :
                    { {xin_store[i+1][NBITS-1]}, xin_store[i+1], 1'b0 };                    
                wire [NBITS+1:0] A_short_in1 =    { {2{ xin[i-5][NBITS-1]}}, xin[i-5] };
                reg [NBITS+1:0] A_short = {NBITS+2{1'b0}};
                // merge the long-delay samples. Sign extend first
                // Long delays are xin_delay[i-1] and xin_delay[i-3]
                wire [NBITS+1:0] A_long_in0_x2 = 
              { xin_delay[i-1][NBITS-1], xin_delay[i-1], 1'b0 };
                wire [NBITS+1:0] A_long_in1 = 
                    { {2{ xin_delay[i-3][NBITS-1]}}, xin_delay[i-3] };
                reg [NBITS+1:0] A_long = {NBITS+2{1'b0}};

                always @(posedge clk_i) begin : PREADD_5_7
                    A_short <= A_short_in0_x2 - A_short_in1;
                    A_long <= A_long_in0_x2 - A_long_in1;
                end
                
                // AREG=2
                // D/M/PREG=1
                // AD_REG=0                
                fir_dsp_core #(.AREG(2),
                               .DREG(1),.MULT_REG(1),.PREG(1),
                               .PREADD_REG(0),
                               .USE_C("FALSE"),
                               .ADD_PCIN("TRUE"))
                    u_i5_7( .clk_i(clk_i),
                            .a_i(`QCONV(A_short, 14, 0, 17, 9)),
                            .d_i(`QCONV(A_long, 14, 0, 17, 9)),
                            .b_i(b_coeff5_7),
                            .pcin_i( i1_3_to_i5_7 ),
                            .p_o(sample_out[i]));                                            
            end
            if (i < 5) begin : ADD_DELAY
                reg [OUTQ_INT+OUTQ_FRAC-1:0] out_delay = {(OUTQ_INT+OUTQ_FRAC){1'b0}};
                always @(posedge clk_i) begin : ADD_DELAY_LOGIC
                    // NOTE NOTE NOTE NOTE NOTE NOTE NOTE
                    // I SHOULD PROBABLY DEAL WITH UNDERFLOW/OVERFLOW HERE
                    out_delay = sample_out[i][ (24-OUTQ_FRAC) +: (OUTQ_INT+OUTQ_FRAC) ];
                end
                assign out_o[(OUTQ_INT+OUTQ_FRAC)*i +: (OUTQ_INT+OUTQ_FRAC)] = out_delay;
            end else begin : NODELAY
                assign out_o[(OUTQ_INT+OUTQ_FRAC)*i +: (OUTQ_INT+OUTQ_FRAC)] = sample_out[i][ (24-OUTQ_FRAC) +: (OUTQ_INT+OUTQ_FRAC)];
            end            
        end
    endgenerate
    
    
endmodule
