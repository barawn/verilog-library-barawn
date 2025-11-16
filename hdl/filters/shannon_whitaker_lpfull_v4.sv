`timescale 1 ns/1 ps

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

// V4 version of the lowpass filter.
// This is still a systolic arrangement but doesn't stack the two
// filters on top of each other - instead they run mostly parallel and
// added together at the end.
//
// This uses more DSPs but zero logic, and with the
// systolic rearrangement it fully utilizes the cascade
// paths, which should make it lower power?
//
// if SATURATE is set, the output data is compressed to
// 12-bits only. The filter itself has a gain of basically 0
// but the phase response allows a properly crafted input
// signal to reach 13 bit range (the sum of the absolute
// value of the coefficients divided by 32768 is 1.543).
//
// The output is still 13 bits, but in that case the top
// bit can be dropped. SATURATE also adds an additional
// clock of delay to the output.
module shannon_whitaker_lpfull_v4 #(parameter INBITS=12,
				                    parameter SATURATE="TRUE",
				                    parameter SHREG="YES",
                                    parameter UPSAMPLE="FALSE",
                                    localparam OUTBITS=INBITS+1,
                                    localparam NSAMPS=8)(
        input   clk_i,
        input   rst_i,      
        input [NSAMPS-1:0][INBITS-1:0]   dat_i,
        output [NSAMPS-1:0][OUTBITS-1:0] dat_o );

    // OK - our goal here is actually to align things as HIGH AS POSSIBLE
    // in the multiplier. The reason for this is that we want as FEW of the
    // top bits flipping neg/pos as we can. The bottom bits will just stay static.
    //
    // The preadder is a 27-bit preadder but it can't overflow, so the
    // two inputs are limited to 26 bits signed.
    // The 1/4 systolic chain needs at least a 27-bit signed value with no preadd. (28 with preadd)
    // The 2/3 systolic chain needs at least a 26-bit signed value with no preadd. (27 with preadd)
    // 
    // We therefore put the preadd into the 2/3 systolic chain, making them both 27-bit
    // signed values. The 1/4 chain gets the round constant.
    //
    // However the 1/4 systolic chain can't fully pad to the top, because of the limited
    // width of the B coefficient. So it only pads 3 bits in the coefficient, and 14 in the
    // A/D inputs, giving 17 total.
    localparam signed [17:0] coeffs[7:0] =
        {   18'd10342,  // B15      7
            -18'd3216,  // B13      6
            18'd1672,   // B11      5
            -18'd949,   // B9       4
            18'd526,    // B7       3
            -18'd263,   // B5       2
            18'd105,    // B3       1
            -18'd23 };   // B1       0
    localparam COEFF_UPSHIFT_14 = 3;
    localparam COEFF_UPSHIFT_23 = 4;
    function [17:0] coeff_shift;
        input [17:0] coeff_in;
        input integer shift;
        integer i;
        begin
            for (i=0;i<18;i=i+1) begin
                if (i < shift) coeff_shift[i] = 0;
                else coeff_shift[i] = coeff_in[i-shift];
            end
        end
    endfunction
    // the overall structure of the filter in super-sample rate is
    // [ B7, B15, B9,  B1,   (  x1 )
    //   B5, B13, B11, B3,   |  x3 |
    //   B3, B11, B13, B5,   |  x5 |
    //   B1,  B9, B15, B7 ]  (  x7 )
    //  z-8 z-16 z-24 z-32
    //
    // which means it's actually the sum of 4 separate systolic
    // filters. Except the parallel structure of rows 1 and 4
    // and 2 and 3 mean that they can be combined in the systolic
    // filter with the same fanout, trivializing the implementation.
    // The systolic nature means we can fully pipeline everything.
    // Nothing after the inputs matters.
    // I would say this means we could run at 500 MHz but that's
    // pointless because it breaks the symmetric structure.

    // The overall fanout here ends up only being 3 for each input
    // initially: two directs, and then a pipeline FF which has
    // larger fanout.
    //
    // The two systolic chains are added together at the end.
    // They run equal in time, so an additional postadd DSP
    // is needed. It doesn't need a multiplier but we want the
    // pattern detector.
    // 
    // 1/4 is only a max of 22 bits signed, so it gets the round
    // constant. 2/3 is a 27-bit number signed.
    //
    wire [INBITS-1:0] data_store[7:0];    // z^-1
    wire [INBITS-1:0] data_store_2[7:0];  // z^-2
    wire [INBITS-1:0] data_store_3[7:0];  // z^-3
    wire [INBITS-1:0] data_store_4[7:0];  // z^-4    - only 3 samples actually need this
    wire [INBITS-1:0] data_in[7:0];
    generate
        genvar i;
        for (i=0;i<8;i=i+1) begin : SL
            wire [47:0] syst0_out;
            wire [47:0] syst1_out;
            // NOTE NOTE NOTE I will implement this in a DSP when I'm sure it works
            // These are both 27 bit signed, but they're aligned one off. syst0 (the 1/4 systolic)
            // has 17 bits of padding, whereas syst1 has 18 bits of padding.
            wire [27:0] final_sum_SE0 = { syst0_out[43], syst0_out[17 +: 27] };
            wire [27:0] final_sum_SE1 = { syst1_out[44], syst1_out[18 +: 27] };
            reg [27:0] final_sum = {28{1'b0}};

            reg [INBITS-1:0] st = {12{1'b0}};
            reg [INBITS-1:0] st2  = {12{1'b0}};
            reg [INBITS-1:0] st3 = {12{1'b0}};
            reg [INBITS-1:0] st4 = {12{1'b0}};
            assign data_in[i] = dat_i[i];
            always @(posedge clk_i) begin : S
                st <= data_in[i];
                st2 <= st;
                st3 <= st2;
                st4 <= st3;
            end
            assign data_store[i] = st;
            assign data_store_2[i] = st2;
            assign data_store_3[i] = st3;
            assign data_store_4[i] = st4;
            // The 1/4 systolic takes in
            // sample 7:    0       /   6       z^-3
            // sample 6:    7z^-1   /   5       z^-3
            // sample 5:    6z^-1   /   4       z^-3
            // sample 4:    5z^-1   /   3       z^-3
            // sample 3:    4z^-1   /   2       z^-3
            // sample 2:    3z^-1   /   1       z^-3
            // sample 1:    2z^-1   /   0       z^-3
            // sample 0:    1z^-1   /   7z^-1   z^-3
            wire [INBITS-1:0] syst0_in = (i>6) ? data_in[i-7] : data_store[i+1];
            wire [INBITS-1:0] syst0_pre = (i>0) ? data_in[i-1] : data_store[i+7];
            // the 2/3 systolic takes in
            // sample 7:    2       /   4       z^-3
            // sample 6:    1       /   3       z^-3
            // sample 5:    0       /   2       z^-3
            // sample 4:    7z^-1   /   1       z^-3
            // sample 3:    6z^-1   /   0       z^-3
            // sample 2:    5z^-1   /   7z^-1   z^-3
            // sample 1:    4z^-1   /   6z^-1   z^-3
            // sample 0:    3z^-1   /   5z^-1   z^-3
            wire [INBITS-1:0] syst1_in = (i>4) ? data_in[i-5] : data_store[i+3];
            wire [INBITS-1:0] syst1_pre = (i>2) ? data_in[i-3] : data_store[i+5];

            //
            // Because we're dropping the preadd reg to save power,
            // the timing looks like
            // --A-->  z^-1 --|
            // --D-->  z^-1 ---> (A+D)z^-1 -> (mult) -> z^-1 -> (coeff*(A+D)z^-2)  --|
            // --C------------------------------------> z^-1 -> (Cz^-1)            --+-- z^-1 -->            
            // So for instance if we add at the second DSP, we have z^-3 timing
            // or a z^-2 difference between the sum and the C input.
            // This is where the center tap gets added anyway. But because we have
            // the delays, we can push it forward one more to the 2 tap and use the store.

            // round=CONSTANT means we just add the rounding constant.
            fourtap_systolic_preadd #(.USE_ADD("FALSE"),
                                      .ROUND("CONSTANT"),
                                      .SHREG(SHREG),
                                      .PREADD_REG(0))
                syst0(  .clk_i(clk_i),
                        .rst_i(rst_i),
                        .dat_i(syst0_in),
                        .preadd_i(syst0_pre),
                        .coeff0_i( coeff_shift(coeffs[3], COEFF_UPSHIFT_14)    ), //  526
                        .coeff1_i( coeff_shift(coeffs[7], COEFF_UPSHIFT_14)    ), //  10342
                        .coeff2_i( coeff_shift(coeffs[4], COEFF_UPSHIFT_14)    ), //  -949
                        .coeff3_i( coeff_shift(coeffs[0], COEFF_UPSHIFT_14)    ), //  -23
                        .p_o(syst0_out));
            fourtap_systolic_preadd #(.USE_ADD(UPSAMPLE == "TRUE" ? "FALSE" : "TRUE"),
                                      .SHREG(SHREG),
                                      .PREADD_REG(0),
                                      .ADD_INDEX(0),
                                      .SCALE_ADD(14 + COEFF_UPSHIFT_23))
                syst1(  .clk_i(clk_i),
                        .rst_i(rst_i),
                        .dat_i(syst1_in),
                        .preadd_i(syst1_pre),
                        .add_i(data_store_3[i]),
                        .coeff0_i( coeff_shift(coeffs[2], COEFF_UPSHIFT_23)    ), //  -263
                        .coeff1_i( coeff_shift(coeffs[6], COEFF_UPSHIFT_23)    ), //  -3216
                        .coeff2_i( coeff_shift(coeffs[5], COEFF_UPSHIFT_23)    ), //  1672
                        .coeff3_i( coeff_shift(coeffs[1], COEFF_UPSHIFT_23)    ), //  105
                        .p_o(syst1_out));

            // NOTE NOTE NOTE NOTE NOTE NOTE NOTE ACTUALLY IMPLEMENT ROUNDING HERE
            reg [11:0] final_sum_sat_round = {12{1'b0}};
            always @(posedge clk_i) begin : FS
                final_sum <= final_sum_SE0 + final_sum_SE1;
                final_sum_sat_round[11] <= final_sum[27];
                if (final_sum[27:26] != 2'b00 && final_sum[27:26] != 2'b11) begin
                    final_sum_sat_round[0 +: 11] <= !final_sum[27];
                end else begin
                    final_sum_sat_round[0 +: 11] <= final_sum[15 +: 11];
                end
            end

            // The final result is 29 bits, but our basic scale is upshifted by 15 bits
            // so 15 +: 12 is what we want prior to round/sat handling.
            assign dat_o[i] = {final_sum_sat_round[11], final_sum_sat_round};
        end
    endgenerate
      
endmodule // shannon_whitaker_lpfull_v4
