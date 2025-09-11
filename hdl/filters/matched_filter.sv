`timescale 1ns / 1ps
`include "dsp_macros.vh"

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

// single channel matched filter for PUEO
//
// REMEMBER: OUR INDICES WORK LIKE:
// 0 IS EARLIEST IN SSR BLOCK
// 7 IS THE LATEST IN SSR BLOCK
//
// The overall matched filter coefficients are:
// h_z = [  -1, -1,  0,  0,  0,  1,  1,  0,
//           0, -1, -1, -1,  0,  1,  1,  1,
//           1,  0, -1, -1, -1,  0,  1,  2,
//           1,  0, -1, -2, -2,  0,  2,  4,
//           0, -4, -4,  1,  4,  1, -2, -1,
//           1,  1 ]
module matched_filter #(parameter NBITS=12,
                        parameter NSAMPS=8)(
        input aclk,
        input [NBITS*NSAMPS-1:0] data_i,
        output [NBITS*NSAMPS-1:0] data_o
    );
    
    // input data delayed
    reg [NBITS*NSAMPS-1:0] data_delayed = {NBITS*NSAMPS{1'b0}};
    // input data doubly-delayed
    reg [NBITS*NSAMPS-1:0] data_ddelayed = {NBITS*NSAMPS{1'b0}};
    
    // vectorized
    wire [NBITS-1:0] x[NSAMPS-1:0];
    wire [NBITS-1:0] x_zminus8[NSAMPS-1:0];
    wire [NBITS-1:0] x_zminus16[NSAMPS-1:0];
    wire [NBITS-1:0] x_zminus1[NSAMPS-1:0];    
    wire [NBITS-1:0] x_zminus15[NSAMPS-1:0];
        
    // 1+z^-1
    wire [NBITS:0] aux_a[NSAMPS-1:0];
    wire [NBITS:0] aux_a_zminus8[NSAMPS-1:0];
    // mixed to create zminus 5 for the b terms
    wire [NBITS:0] aux_a_zminus5[NSAMPS-1:0];

    // n.b. b term inputs have range -4096 to 4094 so they have range -8190 to +8190
    wire [NBITS+1:0] aux_b[NSAMPS-1:0];
    wire [NBITS+1:0] aux_b_zminus8[NSAMPS-1:0];
    wire [NBITS+1:0] aux_b_zminus16[NSAMPS-1:0];

    wire [NBITS:0] aux_c[NSAMPS-1:0];
    wire [NBITS:0] aux_c_zminus8[NSAMPS-1:0];
    wire [NBITS:0] aux_c_zminus16[NSAMPS-1:0];
    
    always @(posedge aclk) begin
        data_delayed <= data_i;
        data_ddelayed <= data_delayed;
    end
    
    generate
        genvar i;
        for (i=0;i<NSAMPS;i=i+1) begin : NL
            assign x[i] = data_i[NBITS*i +: NBITS];
            assign x_zminus8[i] = data_delayed[NBITS*i +: NBITS];
            assign x_zminus16[i] = data_ddelayed[NBITS*i +: NBITS];
            assign x_zminus1[i] = (i==0) ? x_zminus8[NSAMPS+i-1] : x[i-1];
            assign x_zminus15[i] = (i<(NSAMPS-1)) ? x_zminus16[i+1] : x_zminus8[i+1-NSAMPS];
            assign aux_a_zminus5[i] = (i < 5) ? aux_a_zminus8[NSAMPS+i-5] : aux_a[i-5];
            
            reg [NBITS:0] aux_a_sum = {NBITS+1{1'b0}};
            reg [NBITS:0] aux_a_sum_delayed = {NBITS+1{1'b0}};
            reg [NBITS+1:0] aux_b_sum = {NBITS+2{1'b0}};
            reg [NBITS+1:0] aux_b_sum_delayed = {NBITS+2{1'b0}};
            reg [NBITS+1:0] aux_b_sum_ddelayed = {NBITS+2{1'b0}};
            reg [NBITS:0] aux_c_sum = {NBITS+1{1'b0}};
            reg [NBITS:0] aux_c_sum_delayed = {NBITS+1{1'b0}};
            reg [NBITS:0] aux_c_sum_ddelayed = {NBITS+1{1'b0}};
            reg [NBITS:0] aux_c_sum_dddelayed = {NBITS+1{1'b0}};
                        
            assign aux_a[i] = aux_a_sum;
            assign aux_a_zminus8[i] = aux_a_sum_delayed;
            assign aux_b[i] = aux_b_sum;
            assign aux_b_zminus8[i] = aux_b_sum_delayed;
            assign aux_b_zminus16[i] = aux_b_sum_ddelayed;
            // aux_c is base delayed by 1.
            assign aux_c[i] = aux_c_sum_delayed;
            assign aux_c_zminus8[i] = aux_c_sum_ddelayed;
            assign aux_c_zminus16[i] = aux_c_sum_dddelayed;
            
            // The Tx terms are 2a -2b + c
            // range is -10238 to 10237, takes NBITS+3 bits to represent. 
            // The addends have max range NBITS+1 so we need to sign extend two of them.
            reg [NBITS+2:0] Tx = {NBITS+3{1'b0}};
            // Tx_0 has three types 0-2, 3-5, and 6-7
            wire [NBITS-1:0] Tx_0 = (i > 5) ? (x_zminus8[i-6]) : ( (i>2) ? (x_zminus16[i+2]) : (x_zminus8[i+2]));
            // Tx_1 has only 2 types: 0-2 and 3-7
            wire [NBITS:0] Tx_1 = (i > 2) ? (aux_a[i-3]) : (aux_a[i+5]);
            // Tx_2 has 3 types 0-1, 2, and 3-7
            wire [NBITS-1:0] Tx_2 = (i > 2) ? x_zminus8[i-2] : ((i > 1) ? x[i-2] : x_zminus8[i+6]);
            // Now arrange with common width and scaling.
            wire [NBITS+2:0] Two_Tx_0_SE = { {2{Tx_0[NBITS-1]}}, Tx_0, 1'b0 };
            wire [NBITS+2:0] Two_Tx_1_SE = { Tx_1[NBITS], Tx_1, 1'b0 };
            wire [NBITS+2:0] Tx_2_SE = { {3{Tx_2[NBITS-1]}}, Tx_2 };
            
            // the Ty term has span NBITS+2 due to the ternary add:
            // range is -6143 to 6142
            // Each term is multiplied by 4 so we add 4 Ty later instead.
            reg [NBITS+1:0] Ty = {NBITS+2{1'b0}};
            // Ty_0 has 3 types: 0-3, 4-6, and 7
            wire [NBITS-1:0] Ty_0 = (i > 6) ? x_zminus8[i-7] : ( (i>3) ? x_zminus16[i+1] : x_zminus8[i+1] );
            // Ty_1 has 3 types: 0, 1-3, and 4-7
            wire [NBITS:0] Ty_1 = (i > 3) ? aux_a_zminus8[i-1] : ( (i>0) ? aux_a[i-1] : aux_a_zminus8[i+7] );
            // Ty_2 has 2 types: 0-3 and 4-7.
            wire [NBITS-1:0] Ty_2 = (i > 3) ? x_zminus16[i-4] : x_zminus16[i+4];
            // The Tys all have common scaling, but not width. Specify them all here to match the output
            // to avoid stupidity.
            wire [NBITS+1:0] Ty_0_SE = { {2{Ty_0[NBITS-1]}}, Ty_0 };
            wire [NBITS+1:0] Ty_1_SE = { Ty_1[NBITS], Ty_1 };
            wire [NBITS+1:0] Ty_2_SE = { {2{Ty_2[NBITS-1]}}, Ty_2 };
            
            // The Tz term has max 8189 and min -8191 which needs a 14 bit range. or nbits+2.
            // This is because the two x terms have range NBITS+1 when combined and the A term has range NBITS+1
            // yielding NBITS+2.
            reg [NBITS+1:0] Tz = {NBITS+2{1'b0}};
            // Tz_0 has 2 types: 0-4 and 5-7
            wire [NBITS-1:0] Tz_0 = (i > 4) ? x_zminus8[i-5] : x_zminus16[i+3];
            // Tz_1 has 2 types: 0-6 and 7.
            wire [NBITS-1:0] Tz_1 = (i > 6) ? x_zminus8[i-7] : x_zminus16[i+1];
            // Tz_2 has only 1 type.
            wire [NBITS:0] Tz_2 = aux_a_zminus8[i];
            // Same scaling, different widths.
            wire [NBITS+1:0] Tz_0_SE = { {2{Tz_0[NBITS-1]}}, Tz_0 };
            wire [NBITS+1:0] Tz_1_SE = { {2{Tz_1[NBITS-1]}}, Tz_1 };
            wire [NBITS+1:0] Tz_2_SE = { Tz_2[NBITS], Tz_2 };

            // The T term range is tricky because Ty gets upshifted by 2.
            // Tx has range -10238 to 10237
            // Ty has range -24572 to 24568 after scaling
            // Tz has range -8191 to 8189
            // Sum has range -43001 to 42994 which requires 17 bits or NBITS+5
            reg [NBITS+4:0] T_sum = { NBITS+5{1'b0} };
            
            // for the T terms we have 3 types, but now we
            // need to class them out. We only ever need to delay
            // Ty/Tz.
            wire [NBITS+2:0] T_0 = Tx;
            wire [NBITS+1:0] T_1;
            wire [NBITS+1:0] T_2;
            
            // Ty is ONLY delayed in one case: i == 3.
            // This is because the delays go:
            // 4: z^16 z^16 z^24
            // 3: z^16 z^24 z^24
            // 2: z^24 z^24 z^24
            if (i == 3) begin : T1DL
                reg [NBITS+1:0] Ty_delayed = {NBITS+1{1'b0}};
                always @(posedge aclk) begin : LG
                    Ty_delayed <= Ty;
                end
                assign T_1 = Ty_delayed;
            end else begin
                assign T_1 = Ty;
            end
            // 0, 1, and 2 just add direct, everyone else needs Tz delayed.
            if (i > 2) begin : T2DL
                reg [NBITS+1:0] Tz_delayed = {NBITS+1{1'b0}};
                always @(posedge aclk) begin : LG
                    Tz_delayed <= Tz;
                end
                assign T_2 = Tz_delayed;
            end else begin
                assign T_2 = Tz;
            end
            
            // now rescale and sign extend (T0 is 15->16, T1 is a scale, and T2 is 14->16)
            // and then sign extend again to match the sum to avoid silliness.
            wire [NBITS+4:0] T_0_SE = { {2{T_0[NBITS+2]}}, T_0 };
            wire [NBITS+4:0] Four_T_1_SE = { T_1[NBITS+1], T_1, 2'b00 };
            wire [NBITS+4:0] T_2_SE = { {3{T_2[NBITS+1]}}, T_2 };
            
            // The B inputs are symmetric so they have range +/- 8190, so TB = -24570 to 24570
            reg [NBITS+3:0] TB = {NBITS+4{1'b0}};
            // TB_0 is always the same.
            wire [NBITS+1:0] TB_0 = aux_b[i];
            // TB_1 flips at 2 and is base zminus8
            wire [NBITS+1:0] TB_1 = (i > 1) ? aux_b_zminus8[i-2] : aux_b_zminus16[i+6];
            // and TB_2 flips at 5 and is base zminus8
            wire [NBITS+1:0] TB_2 = (i > 4) ? aux_b_zminus8[i-5] : aux_b_zminus16[i+3];

            // sign extension
            wire [NBITS+3:0] TB_0_SE = { {2{TB_0[NBITS+1]}}, TB_0 };
            wire [NBITS+3:0] TB_1_SE = { {2{TB_1[NBITS+1]}}, TB_1 };
            wire [NBITS+3:0] TB_2_SE = { {2{TB_2[NBITS+1]}}, TB_2 };
            
            // TC inputs are just an add of 4 NBITS+1 guys so they have range NBITS+3
            reg [NBITS+2:0] TC = {NBITS+3{1'b0}};
            // All the TC inputs special-case 7 so that they don't need a delay to join with TB.
            // TC_0 has 3 cases 0, 1-6, and 7
            wire [NBITS:0] TC_0 = (i > 6) ? aux_c_zminus8[i-1] : ((i>0) ? aux_c[i-1] : aux_c_zminus8[i+7]);
            // TC_1 also has 3 cases: 0-3, 4-6, and 7
            wire [NBITS:0] TC_1 = (i > 6) ? aux_c_zminus16[i-4] : ((i>3) ? aux_c_zminus8[i-4] : aux_c_zminus16[i+4]);
            // TC_2 only has 2 cases: 0-6 and 7. Case 7 looks weird because it should be zminus8[i-7] but add'l delay as above.
            wire [NBITS:0] TC_2 = (i > 6) ? aux_c_zminus16[i-7] : aux_c_zminus16[i+1];
            
            // sign extend to avoid silliness
            wire [NBITS+2:0] TC_0_SE = { {2{TC_0[NBITS]}}, TC_0 };
            wire [NBITS+2:0] TC_1_SE = { {2{TC_1[NBITS]}}, TC_1 };
            wire [NBITS+2:0] Two_TC_2_SE = { TC_2[NBITS], TC_2, 1'b0 };
                            
            // And now to feed into the U adder we need to align TB, TC
            // and add in the free term.
            // TB is 16 bits, TC is 15 bits, and the free term is 12 bits. So this is 17 bits.
            reg [NBITS+4:0] U_sum = {NBITS+5{1'b0}};
            // for simplicity we treat this stuff the same as before
            wire [NBITS+3:0] U_0 = TB;
            wire [NBITS+2:0] U_1;
            if (i < 7) begin : HD2
                reg [NBITS+2:0] TC_delayed = {NBITS+3{1'b0}};
                always @(posedge aclk) begin : LG
                    TC_delayed <= TC;
                end
                assign U_1 = TC_delayed;
            end else begin : TL2
                assign U_1 = TC;            
            end
	    // U2 needs a long delay, either 5 or 6 clocks.
	    // so the address is 3 or 4 with the extra FF
	    wire [NBITS-1:0] U_2_dly;
	    reg [NBITS-1:0]  U_2 = {NBITS{1'b0}};	   
	    srlvec #(.NBITS(12))
	        u_u2delay_srl(.clk(aclk),
			      .ce(1'b1),
			      .a((i<6) ? 4 : 3),
			      .din((i<6) ? x[i+2] : x[i-6]),
			      .dout(U_2_dly));
            // and sign extend 0: 16->17, 1:15->17, 2: 12->17
            wire [NBITS+4:0] U_0_SE = { U_0[NBITS+3], U_0 };
            wire [NBITS+4:0] U_1_SE = { {2{U_1[NBITS+2]}}, U_1 };
            wire [NBITS+4:0] U_2_SE = { {5{U_2[NBITS-1]}}, U_2 };

            // Only thing left to do is delay T_sum by 5/6 clocks and feed it and U_sum into
            // a half-DSP. i=0-2 have the additional delay (6 instead of 5). We don't use the
            // DSP regs because it's an odd number
            // This in the end uses 4 DSPs per channel or 32 total.
            // If we trade this up to 128 DSPs total we can drop the entire T/U path
            // because we can use the preadder + C port to pick up 3 inputs and add all 6
            // at once. But the downside is we need to delay ALL of the T_sum inputs because
            // we can't possibly eat 5 clocks of latency anywhere. 

            wire [NBITS+4:0] T_delayed;
            reg [NBITS+4:0] T_delayed_sum = {NBITS+5{1'b0}};
            // The T outputs need a delay of 4 clocks (for i > 2) or 5 clocks (for i <= 2)
            // Without the FF this would be an address of 3 or 4
            // With the FFs this is an address of 2 or 3
            srlvec #(.NBITS(17))
                u_tdelay_srl(.clk(aclk),
                             .ce(1'b1),
                             .a((i>2) ? 4'd2 : 4'd3),
                             .din(T_sum),
                             .dout(T_delayed));

            // 17/16/15 == 111 or 000
            reg [NBITS+5:0] M_sum = {NBITS+6{1'b0}};
            wire saturation = (M_sum[17:15] != 3'b000) && (M_sum[17:15] != 3'b111);
            reg [NBITS-1:0] M_sat_and_scale = {NBITS{1'b0}};
            wire [NBITS+5:0] M_0_SE = {T_delayed_sum[NBITS+4], T_delayed_sum};
            wire [NBITS+5:0] M_1_SE = {U_sum[NBITS+4], U_sum};
            
            always @(posedge aclk) begin : LG
                // force the sign extension to avoid stupidity.
                aux_a_sum <= {x[i][NBITS-1], x[i]} + {x_zminus1[i][NBITS-1],x_zminus1[i]};
                aux_b_sum <= {aux_a[i][NBITS],aux_a[i]} - {aux_a_zminus5[i][NBITS],aux_a_zminus5[i]};
                aux_c_sum <= {x[i][NBITS-1],x[i]} - {x_zminus15[i][NBITS-1],x_zminus15[i]};
                
                aux_a_sum_delayed <= aux_a_sum;
                aux_b_sum_delayed <= aux_b_sum;
                aux_b_sum_ddelayed <= aux_b_sum_delayed;
                aux_c_sum_delayed <= aux_c_sum;
                aux_c_sum_ddelayed <= aux_c_sum_delayed;
                aux_c_sum_dddelayed <= aux_c_sum_ddelayed;
                
                Tx <= Two_Tx_0_SE - Two_Tx_1_SE - Tx_2_SE;
                Ty <= Ty_0_SE - Ty_1_SE + Ty_2_SE;
                Tz <= Tz_0_SE - Tz_1_SE + Tz_2_SE;
                
                T_sum <= T_0_SE + Four_T_1_SE + T_2_SE;
                
                TB <= TB_2_SE - TB_0_SE - TB_1_SE;
                
                TC <= Two_TC_2_SE - TC_0_SE - TC_1_SE;

	            U_2 <= U_2_dly;	       
	       
                U_sum <= U_0_SE + U_1_SE + U_2_SE;
                
                T_delayed_sum <= T_delayed;
                
                M_sum <= M_0_SE + M_1_SE;
                
                if (saturation) begin
                    // this is always the same
                    M_sat_and_scale[NBITS-1] <= M_sum[4+NBITS-1];
                    // this is always the opposite: so it's either 011111111111
                    //                                          or 100000000000
                    M_sat_and_scale[NBITS-2:0] <= ~M_sum[4+NBITS-1];
                end else begin
                    // FIGURE OUT ROUNDING!!!
                    M_sat_and_scale <= M_sum[4 +: NBITS];
                end
            end                             
                                    
            assign data_o[NBITS*i +: NBITS] = M_sat_and_scale;
	   
        end
    endgenerate
                
endmodule
