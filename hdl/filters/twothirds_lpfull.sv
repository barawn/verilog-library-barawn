`timescale 1 ns/1 ps
// Two-thirds band filter. This works on an SSR4 input only.
//
// If SATURATE is set, the ouput bits are compressed to 12
// bits - even though they're 13 bits, the top bit is a copy
// of bit 11.
//
// clk_phase_i is needed to transfer samples from
// 4 samples/clock to 6 samples/clock. This needs
// to be global, because it adds an overall delay,
// and that needs to be the same everywhere.
// (e.g. if it takes 12 clocks through the filter,
//  that's 011 011 011 011 011 011
//         = 16 clocks in the main clock, but if another
//  filter does 110 110 110 110 110 11
//         = 15 clocks in the main clock.)
// We want 6 samples/clock because of the filter
// structure - it aligns all of the zero taps onto
// the same samples, allowing the filter to be
// arranged systolic with a preadd.
module twothirds_lpfull #(parameter INBITS=12,
                          parameter SATURATE = "TRUE",
                          localparam OUTBITS=INBITS+1,
                          localparam NSAMPS=4)(
        input   clk_i,
        input   clk_phase_i,
        input   rst_i,
        input [NSAMPS-1:0][INBITS-1:0]   dat_i,
        output [NSAMPS-1:0][OUTBITS-1:0] dat_o );

    // Overall
    // z^0   z^-1    z^-2  z^-3  z^-4     z^-5
    // 0     -18     44    0     -137     209
    // 0     -423    578   0     -1054    1446
    // 0     -3258   6710  16384  6710   -3258
    // 0      1446  -1054  0      578    -423
    // 0      209   -137   0      44     -18
    //
    localparam signed [17:0] coeffs[9:0] =
        {   18'd6710,   // B14      9
	    -18'd3258,  // B13      8
	    18'd1446,  // B11      7
            -18'd1054,  // B10      6
            18'd578,   // B8      5
            -18'd423,   // B7       4
            18'd209,    // B5       3
            -18'd137,   // B4       2
            18'd44,    // B2       1
            -18'd18 };   // B1       0

    localparam COEFF_UPSHIFT = 3;
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
    // The 2/3rds lowpass first has to move from 4x SSR to 6x SSR.
    // This means that 1 of the 3 clocks is unused, so unlike the
    // halfband, we need to use the clock enable.

    wire [5:0][INBITS-1:0] dat_ssr6;
    wire		   dat_ssr6_ce;

    lp_four_to_six u_ssr6(.clk_i(clk_i),
			  .clk_phase_i(clk_phase_i),
			  .dat_i(dat_i),
			  .dat_o(dat_ssr6),
			  .ce_o(dat_ssr6_ce));   
   
    wire [5:0][INBITS-1:0] out_ssr6;
   
   
    // The SSR structure of the filter is
    // [ B1  B2  B4   B5  ]  ( x1 )
    // | B7  B8  B10  B11 |  | x2 |
    // | B13 B14 B14  B13 |  | x4 |
    // | B11 B10 B8   B7  |  ( x5 )   
    // [ B5  B4  B2   B1  ]
    //
    // As before, it's actually the sum of 4 separate systolic
    // filters. Except the parallel structure of rows 1 and 4
    // and 2 and 3 mean that they can be combined in the systolic
    // filter with the same fanout, trivializing the implementation.
    // The systolic nature means we can fully pipeline everything.
    // Nothing after the inputs matters.

    // The overall fanout here ends up only being 3 for each input
    // initially: two directs, and then a pipeline FF which has
    // larger fanout.
    //
    generate
        genvar i;
        for (i=0;i<6;i=i+1) begin : SL	   
            // Overall inputs:
            // sample 5: 4/0       and 3/1      center 2 at z^-12
	    // sample 4: 3/5z^-6   and 2/0      center 1 at z^-12
	    // sample 3: 2/4z^-6   and 1/5z^-6  center 0 at z^-12
	    // sample 2: 1/3z^-6   and 0/4z^-6  center 5 at z^-18
	    // sample 1: 0/2z^-6   and 5z^-6/3z^-6   center 4 at z^-18
	    // sample 0: 5z^-6/1z^-6 and 4z^-6/2z^-6 center 3 at z^-18
	    //
	    // However, note that in order to get the add at the right point,
	    // since all of the DSPs have the A/D+preadder + multiplier register
	    // before the ALU and the add path only has the C register,
	    // this means we need an additional 2 clocks delay on the center
	    // (or three if we're before sample 3). So we need to delay the
	    // add by 3 or 4 clocks.
            //
            // Note that we don't bother absorbing any delays anywhere
            // since these registers are common, and so many of them
            // will just be absorbed. But not absorbing the delay
            // means that it can absorb them _as necessary_.
            wire [INBITS-1:0] sys0_base = dat_ssr6[(i+5)%6];
            wire [INBITS-1:0] pre0_base = dat_ssr6[(i+1)%6];
	 
            wire [INBITS-1:0] sys1_base = dat_ssr6[(i+4)%6];
            wire [INBITS-1:0] pre1_base = dat_ssr6[(i+2)%6];

            wire [INBITS-1:0] add_in_base = dat_ssr6[(i+3)%6];	 
            reg [INBITS-1:0]  add_in_store = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store2 = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store3 = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store4 = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store5 = {INBITS{1'b0}};
            always @(posedge clk_i) begin : LG
	           if (dat_ssr6_ce) begin
                    add_in_store <= add_in_base;     // one clock delay
                    add_in_store2 <= add_in_store;   // two clock delay
                    add_in_store3 <= add_in_store2;  // three clock delay
                    add_in_store4 <= add_in_store3;  // four clock delay
                    add_in_store5 <= add_in_store4;  // five clock delay
                end	       
            end            

            wire [INBITS-1:0] add_in = (i < 3) ? add_in_store5 : add_in_store4;

            wire [INBITS-1:0] sys0_in;
            wire [INBITS-1:0] pre0_in;

            wire [INBITS-1:0] sys1_in;
            wire [INBITS-1:0] pre1_in; 

            wire [INBITS-1:0] sys1_dly;
            wire [INBITS-1:0] pre1_dly;
            
            // sys0 assignment
            if (i > 0) begin : SYS0_DIRECT
               assign sys0_in = sys0_base;	    
            end else begin : SYS0_STORE
               // everyone now needs sys0 registered
               reg [INBITS-1:0] sys0_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
		  if (dat_ssr6_ce)
                    sys0_store <= sys0_base;	       
               end
               assign sys0_in = sys0_store;
            end
            
            // pre0 assignment
            // 5 takes direct
            if (i > 4) begin : PRE0_DIRECT
               assign pre0_in = pre0_base;
            end else begin : PRE0_STORE
               reg [INBITS-1:0] pre0_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
		  if (dat_ssr6_ce)
                    pre0_store <= pre0_base;
               end
               assign pre0_in = pre0_store;	       
            end
            
            // sys1 assignment
            // for sys1 everyone past 1 just takes it direct
            if (i > 1) begin : SYS1_DIRECT
               assign sys1_in = sys1_base;	    
            end else begin : SYS1_STORE
               reg [INBITS-1:0] sys1_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
                  if (dat_ssr6_ce)
		    sys1_store <= sys1_base;	       
               end
               assign sys1_in = sys1_store;
            end
            
            // pre1 assignment
            // and for pre1 everyone past 3 takes it direct
            if (i > 3) begin : PRE1_DIRECT
               assign pre1_in = pre1_base;	    
            end else begin : PRE1_STORE
               reg [INBITS-1:0] pre1_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
                  if (dat_ssr6_ce)
		    pre1_store <= pre1_base;
               end
               assign pre1_in = pre1_store;	    
            end
            
            // delays
            // probably change these to actual register chains
            // and let the synthesizer figure out what can be converted?
            // maybe? no idea?!?

	    // NOTE NOTE NOTE NOTE I HAVE NO IDEA IF THESE DELAYS ARE CORRECT, TO BE TESTED
            srlvec #(.NBITS(12))
                u_sys1_dly(.clk(clk_i),
                           .ce(dat_ssr6_ce),
                           .a(4),
                           .din(sys1_in),
                           .dout(sys1_dly));
            srlvec #(.NBITS(12))
                u_pre1_dly(.clk(clk_i),
                           .ce(dat_ssr6_ce),
                           .a(4),
                           .din(pre1_in),
                           .dout(pre1_dly));
            
            // ok now we just need the filters
            wire [47:0] cascade;	 
            fivetap_systolic_preadd #(.USE_ADD("TRUE"),
				      .USE_CE("TRUE"),
                                      .ADD_INDEX(0),
                                      .SCALE_ADD(14+COEFF_UPSHIFT))
                syst0(  .clk_i(clk_i),
			.ce_i(dat_ssr6_ce),
                        .rst_i(rst_i),
                        .dat_i(sys0_in),
                        .preadd_i(pre0_in),
                        .add_i(add_in),
                        .coeff0_i( coeff_shift(coeffs[0], COEFF_UPSHIFT)    ), //  -18
                        .coeff1_i( coeff_shift(coeffs[4], COEFF_UPSHIFT)    ), //  -423
                        .coeff2_i( coeff_shift(coeffs[8], COEFF_UPSHIFT)    ), //  -3258
                        .coeff3_i( coeff_shift(coeffs[7], COEFF_UPSHIFT)    ), //  1446
			.coeff4_i( coeff_shift(coeffs[3], COEFF_UPSHIFT)    ), //  209
                        .pc_o(cascade));
            wire [47:0] data_out;
            wire [12:0] last_out;
            fivetap_systolic_preadd #(.CASCADE("TRUE"),
				      .USE_CE("TRUE"),
                                      .ROUND("TRUE"),
                                      .SCALE_OUT(15+COEFF_UPSHIFT))
                syst1(  .clk_i(clk_i),
                        .ce_i(dat_ssr6_ce),
			.rst_i(rst_i),
                        .dat_i(sys1_dly),
                        .preadd_i(pre1_dly),
                        .coeff0_i( coeff_shift(coeffs[1], COEFF_UPSHIFT)    ), //  44
                        .coeff1_i( coeff_shift(coeffs[5], COEFF_UPSHIFT)    ), //  578
                        .coeff2_i( coeff_shift(coeffs[9], COEFF_UPSHIFT)    ), //  6710
                        .coeff3_i( coeff_shift(coeffs[6], COEFF_UPSHIFT)    ), //  -1054
			.coeff4_i( coeff_shift(coeffs[2], COEFF_UPSHIFT)    ), //  -137
                        .pc_i(cascade),
                        .dat_o(last_out),
                        .p_o(data_out));
	   
	    // The saturation logic is always present, but if it's not selected,
	    // it's not used and will be trimmed away.
            wire saturated = last_out[12] ^ last_out[11];
            reg [11:0] dat_final = {12{1'b0}};
            always @(posedge clk_i) begin : SAT
	        if (dat_ssr6_ce) begin
                   if (saturated) begin
                      dat_final[11] <= last_out[12];
                      dat_final[10:0] <= {11{~last_out[12]}};
                   end else dat_final <= last_out[11:0];
		end	       
            end
            assign out_ssr6[i] = (SATURATE == "TRUE") ? {dat_final[11],dat_final} : last_out[12:0];
        end

        if (SATURATE == "TRUE") begin : SAT
            wire [NSAMPS-1:0][INBITS-1:0] tmp;
            lp_six_to_four #(.NBITS(INBITS))
                u_ssr4(.clk_i(clk_i),
                       .ce_i(dat_ssr6_ce),
                       .dat_i( { out_ssr6[5][11:0],
                                 out_ssr6[4][11:0],
                                 out_ssr6[3][11:0],
                                 out_ssr6[2][11:0],
                                 out_ssr6[1][11:0],
                                 out_ssr6[0][11:0] } ),
                       .dat_o(tmp));
            assign dat_o[0][0 +: INBITS] = tmp[0];
            assign dat_o[0][12] = tmp[0][11];
            assign dat_o[1][0 +: INBITS] = tmp[1];
            assign dat_o[1][12] = tmp[1][11];
            assign dat_o[2][0 +: INBITS] = tmp[2];
            assign dat_o[2][12] = tmp[2][11];
            assign dat_o[3][0 +: INBITS] = tmp[3];
            assign dat_o[3][12] = tmp[3][11];
        end else begin : NSAT
            // and then back to 4 per
            lp_six_to_four #(.NBITS(OUTBITS))
               u_ssr4(.clk_i(clk_i),
                      .ce_i(dat_ssr6_ce),
                      .dat_i(out_ssr6),
                      .dat_o(dat_o));    
        end
    endgenerate

       
endmodule // twothirds_lpfull
