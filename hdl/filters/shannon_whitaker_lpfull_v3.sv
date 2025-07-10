`timescale 1 ns/1 ps
// V3 version of the lowpass filter.
// This uses more DSPs but zero logic, and with the
// systolic rearrangement it fully utilizes the cascade
// paths, which should make it lower power?
module shannon_whitaker_lpfull_v3 #(parameter INBITS=12,
				    parameter OUTBITS=12,
				    localparam NSAMPS=8)
   (  input                            clk_i,
      input [NSAMPS-1:0][INBITS-1:0]   dat_i,
      output [NSAMPS-1:0][OUTBITS-1:0] dat_o );


   localparam signed [7:0][17:0] coeffs =
	      { 10342,  // B15
		-3216,  // B13
		1672,   // B11
		-949,   // B9
		526,    // B7
		-263,   // B5
		105,    // B3
		23 };   // B1
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
      genvar			       i;
      for (i=0;i<1;i=i+1) begin : SL
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

	 wire [INBITS-1:0] sys0_in;
	 wire [INBITS-1:0] sys1_in;
	 wire [INBITS-1:0] pre0_in;
	 wire [INBITS-1:0] pre1_in; 

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

	 // ADD THE CENTER TAP ADD STUFF LATER

	 // ok now we just need the filters
	 wire [47:0] cascade;	 
	 fourtap_systolic_preadd 
	   syst0(.clk_i(clk),
		 .rst_i(rst),
		 .dat_i(sys0_in),
		 .preadd_i(pre0_in),
		 .coeff0_i(    526    ),
		 .coeff1_i(  10342    ),
		 .coeff2_i(   -949    ),
		 .coeff3_i(    -23    ),
		 .pc_o(cascade));
	 wire [47:0] data_out;	 
	 fourtap_systolic_preadd #(.CASCADE("TRUE"))
	   syst1(.clk_i(clk),
		 .rst_i(rst),
		 .dat_i(sys1_in),
		 .preadd_i(pre1_in),
		 .coeff0_i(   -263    ),
		 .coeff1_i(  -3216    ),
		 .coeff2_i(   1672    ),
		 .coeff3_i(    105    ),
		 .pc_i(cascade),
		 .p_o(data_out));
	 // FIX THIS WITH ROUNDING CRAP
	 assign dat_o[i] = data_out;	 
      end
   endgenerate
   
   
endmodule // shannon_whitaker_lpfull_v3
