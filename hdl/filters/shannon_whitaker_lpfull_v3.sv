`timescale 1 ns/1 ps
// V3 version of the lowpass filter.
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
module shannon_whitaker_lpfull_v3 #(parameter INBITS=12,
				    parameter SATURATE="TRUE",
                                    localparam OUTBITS=INBITS+1,
                                    localparam NSAMPS=8)(
        input   clk_i,
        input   rst_i,      
        input [NSAMPS-1:0][INBITS-1:0]   dat_i,
        output [NSAMPS-1:0][OUTBITS-1:0] dat_o );

    localparam signed [17:0] coeffs[7:0] =
        {   18'd10342,  // B15      7
            -18'd3216,  // B13      6
            18'd1672,   // B11      5
            -18'd949,   // B9       4
            18'd526,    // B7       3
            -18'd263,   // B5       2
            18'd105,    // B3       1
            -18'd23 };   // B1       0
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
    generate
        genvar i;
        for (i=0;i<8;i=i+1) begin : SL
            // For everyone except samples 7 and 0, the first systolic
            // needs an extra FF. We always do this with the direct
            // systolic because it will just share with the preadded pipes
            // in the others if it needs to.
            
            // The adjusted delays for the second systolic are embedded
            // in the delay chain. The second systolic obviously needs
            // a total delay of 4 registers, and then 2 more get added
            // in the filter core right now. We'll use an SRL vec for
            // those delays and see what happens.
            
            // The center tap for each sample needs to be added
            // with z^-16 timing: the C reg means that it's presented
            // to the ALU with z^-24 timing - but it bypasses ADREG/MREG.
            
            // We could just use the direct input and put it into the
            // first DSP, but there's no downside to registering it
            // and putting it into the second one.
            
            // This means the filter coefficients are reversed from my
            // original testbench:
            // filter 0: 526, 10342, -949, -23
            // filter 1: -263, -3216, 1672, 105
            
            // Overall inputs:
            // sample 7: 0/6       and 2/4      center 7 at z^-24
            // sample 6: 7z^-8/5   and 1/3      center 6 at z^-24
            // sample 5: 6z^-8/4   and 0/2      center 5 at z^-24
            // sample 4: 5z^-8/3   and 7z^-8/1  center 4 at z^-24
            // sample 3: 4z^-8/2   and 6z^-8/0  center 3 at z^-24
            // sample 2: 3z^-8/1   and 5z^-8/7z^-8      center 2 at z^-24
            // sample 1: 2z^-8/0   and 4z^-8/6z^-8      center 1 at z^-24
            // sample 0: 1z^-8/7z^-8 and 3z^-8/5z^-8      center 0 at z^-24
            //
            // Note that we don't bother absorbing any delays anywhere
            // since these registers are common, and so many of them
            // will just be absorbed. But not absorbing the delay
            // means that it can absorb them _as necessary_.
            wire [INBITS-1:0] sys0_base = dat_i[(i+1)%8];
            wire [INBITS-1:0] pre0_base = dat_i[(i+7)%8];	 
            wire [INBITS-1:0] sys1_base = dat_i[(i+3)%8];
            wire [INBITS-1:0] pre1_base = dat_i[(i+5)%8];
            wire [INBITS-1:0] add_in_base = dat_i[i];	 
            reg [INBITS-1:0]  add_in_store = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store2 = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store3 = {INBITS{1'b0}};
            reg [INBITS-1:0]  add_in_store4 = {INBITS{1'b0}};
            always @(posedge clk_i) begin : LG
                add_in_store <= add_in_base;
                add_in_store2 <= add_in_store;
                add_in_store3 <= add_in_store2;
                add_in_store4 <= add_in_store3;
            end            

            wire [INBITS-1:0] add_in = add_in_store4;
            wire [INBITS-1:0] sys0_in;
            wire [INBITS-1:0] pre0_in;

            wire [INBITS-1:0] sys1_in;
            wire [INBITS-1:0] pre1_in; 

            wire [INBITS-1:0] sys1_dly;
            wire [INBITS-1:0] pre1_dly;
            
            // sys0 assignment
            if (i > 6) begin : SYS0_DIRECT
               assign sys0_in = sys0_base;	    
            end else begin : SYS0_STORE
               // everyone now needs sys0 registered
               reg [INBITS-1:0] sys0_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
                  sys0_store <= sys0_base;	       
               end
               assign sys0_in = sys0_store;
            end
            
            // pre0 assignment
            // everyone past 0 just takes pre0 directly
            if (i > 0) begin : PRE0_DIRECT
               assign pre0_in = pre0_base;
            end else begin : PRE0_STORE
               reg [INBITS-1:0] pre0_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
                  pre0_store <= pre0_base;
               end
               assign pre0_in = pre0_store;	       
            end
            
            // sys1 assignment
            // for sys1 everyone past 4 just takes it direct
            if (i > 4) begin : SYS1_DIRECT
               assign sys1_in = sys1_base;	    
            end else begin : SYS1_STORE
               reg [INBITS-1:0] sys1_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
                  sys1_store <= sys1_base;	       
               end
               assign sys1_in = sys1_store;
            end
            
            // pre1 assignment
            // and for pre1 everyone past 2 takes it direct
            if (i > 2) begin : PRE1_DIRECT
               assign pre1_in = pre1_base;	    
            end else begin : PRE1_STORE
               reg [INBITS-1:0] pre1_store = {INBITS{1'b0}};
               always @(posedge clk_i) begin : LG
                  pre1_store <= pre1_base;
               end
               assign pre1_in = pre1_store;	    
            end
            
            // delays
            // probably change these to actual register chains
            // and let the synthesizer figure out what can be converted?
            // maybe? no idea?!?
            srlvec #(.NBITS(12))
                u_sys1_dly(.clk(clk_i),
                           .ce(!rst_i),
                           .a(3),
                           .din(sys1_in),
                           .dout(sys1_dly));
            srlvec #(.NBITS(12))
                u_pre1_dly(.clk(clk_i),
                           .ce(!rst_i),
                           .a(3),
                           .din(pre1_in),
                           .dout(pre1_dly));
            
            // ADD THE CENTER TAP ADD STUFF LATER
            
            // ok now we just need the filters
            wire [47:0] cascade;	 
            fourtap_systolic_preadd #(.USE_ADD("TRUE"),
                                      .ADD_INDEX(0),
                                      .SCALE_ADD(14+COEFF_UPSHIFT))
                syst0(  .clk_i(clk_i),
                        .rst_i(rst_i),
                        .dat_i(sys0_in),
                        .preadd_i(pre0_in),
                        .add_i(add_in),
                        .coeff0_i( coeff_shift(coeffs[3], COEFF_UPSHIFT)    ), //  526
                        .coeff1_i( coeff_shift(coeffs[7], COEFF_UPSHIFT)    ), //  10342
                        .coeff2_i( coeff_shift(coeffs[4], COEFF_UPSHIFT)    ), //  -949
                        .coeff3_i( coeff_shift(coeffs[0], COEFF_UPSHIFT)    ), //  -23
                        .pc_o(cascade));
            wire [47:0] data_out;
            // the output data can range from -3161 to +3159: we don't care, so we
            // again cap off at 12 bits. Note that in order to actually saturate you need
            // to have a maximal amplitude bandlimited pulse so it's pretty unlikely.
            wire [12:0] last_out;
            fourtap_systolic_preadd #(.CASCADE("TRUE"),
                                      .ROUND("TRUE"),
                                      .SCALE_OUT(15+COEFF_UPSHIFT))
                syst1(  .clk_i(clk_i),
                        .rst_i(rst_i),
                        .dat_i(sys1_dly),
                        .preadd_i(pre1_dly),
                        .coeff0_i( coeff_shift(coeffs[2], COEFF_UPSHIFT)    ), //  -263
                        .coeff1_i( coeff_shift(coeffs[6], COEFF_UPSHIFT)    ), //  -3216
                        .coeff2_i( coeff_shift(coeffs[5], COEFF_UPSHIFT)    ), //  1672
                        .coeff3_i( coeff_shift(coeffs[1], COEFF_UPSHIFT)    ), //  105
                        .pc_i(cascade),
                        .dat_o(last_out),
                        .p_o(data_out));
	   
	    // The saturation logic is always present, but if it's not selected,
	    // it's not used and will be trimmed away.
            wire saturated = last_out[12] ^ last_out[11];
            reg [11:0] dat_final = {12{1'b0}};
            always @(posedge clk_i) begin : SAT
                if (saturated) begin
                    dat_final[11] <= last_out[12];
                    dat_final[10:0] <= {11{~last_out[12]}};
                end else dat_final <= last_out[11:0];
            end
            assign dat_o[i] = (SATURATE == "TRUE") ? {dat_final[11],dat_final} : last_out[12:0];
        end
    endgenerate
   
   
endmodule // shannon_whitaker_lpfull_v3
