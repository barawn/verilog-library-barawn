`timescale 1ns / 1ps

//! @title 4 tap systolic filter with preadder, single add, and output round
//! @author Patrick Allison (dbarawn@gmail.com)
module fourtap_systolic_preadd #( 
                  parameter CASCADE = "FALSE",    //! use input cascade for first tap
				  parameter ROUND = "FALSE",      //! round the final tap to output bits
				  parameter USE_ADD = "FALSE",    //! use the add_i input to add a value
				  parameter SCALE_ADD = 0,        //! number of bits to upshift the add_i input
				  parameter SCALE_OUT = 0,        //! number of bits to downshift the output
				  parameter [1:0] ADD_INDEX = 0,  //! index to add the add_i input at 
				  localparam NBITS = 12,          //! number of bits in input and (output-1)
				  parameter OUTBITS = NBITS+1,    //! actual number of output bits (sometimes varies)
				  parameter CLKTYPE = "NONE")     //! clocktype for magic clock crossing
	  ( input	  clk_i,             //! filter clock
	    input     rst_i,             //! force DSPs into reset
	    input [NBITS-1:0]  dat_i,	 //! input to the systolic filter
	    input [NBITS-1:0]  preadd_i, //! preadd for symmetric SSR systolics with SSR a multiple of 4
	    input [NBITS-1:0]  add_i,    //! value to be added at a specific tap (center tap for symmetrics)
	    input [17:0]  coeff0_i,      //! coefficient of first DSP
	    input [17:0]  coeff1_i,      //! coefficient of second DSP
	    input [17:0]  coeff2_i,      //! coefficient of third DSP
	    input [17:0]  coeff3_i,      //! coefficient of fourth DSP
	    input [47:0]  pc_i,          //! cascade input if CASCADE == "TRUE"
	    output [OUTBITS-1:0] dat_o,      //! data output
	    output [47:0] p_o,           //! output of last DSP
	    output [47:0]  pc_o          //! cascade output of last DSP
      );
   
   // the multiplier takes in an 18-bit coefficient and a
   // 27 bit value to multiply, producing a 45 bit output.
   // We align to the top of the adder to reduce bit
   // switching. In addition, the preadder cannot saturate
   // so we need margin on the A/D inputs.
   // So for instance if we have a 12 bit input, A/D are
   // scaled up by 14 bits. So we need to scale up the 
   // coefficient by the same amount and also add SCALE_ADD
   // bits (because the center tap is typically scaled to
   // a power of 2).
   localparam ADD_PAD_BITS = SCALE_ADD + (26 - NBITS);
   wire [47:0] add_pad = (ADD_PAD_BITS + NBITS < 48) ?
        // need to sign extend at the top
        { {(48-ADD_PAD_BITS-NBITS){add_i[NBITS-1]}},
          add_i,
          {ADD_PAD_BITS{1'b0}} } :
        // don't need to add bits at the top
        { add_i, {ADD_PAD_BITS{1'b0}}};
   
   localparam USE_C0 = (USE_ADD == "TRUE") && ADD_INDEX == 2'd0 ? "TRUE" : "FALSE";
   localparam USE_C1 = (USE_ADD == "TRUE") && ADD_INDEX == 2'd1 ? "TRUE" : "FALSE";
   localparam USE_C2 = (USE_ADD == "TRUE") && ADD_INDEX == 2'd2 ? "TRUE" : "FALSE";
   localparam USE_C3 = (USE_ADD == "TRUE") && ADD_INDEX == 2'd3 ? "TRUE" : "FALSE";
   
   localparam USE_RND_2 = ((USE_ADD == "TRUE") && (ADD_INDEX == 2'd3)) ? ROUND : "FALSE";
   localparam USE_RND_3 = ((USE_ADD != "TRUE") || (ADD_INDEX != 2'd3)) ? ROUND : "FALSE";


   // Our output bits have (26-NBITS) useless bits at the bottom.
   // And then we move the decimal point SCALE_OUT up
   // For convergent rounding we need (26-NBITS)+SCALE_OUT-1 ones in the bottom.
   localparam CONVERGENT_RND_ONES = (26-NBITS)+SCALE_OUT-1;
   localparam [47:0] RND_CONST = {
        {(48-CONVERGENT_RND_ONES){1'b0}},
        {CONVERGENT_RND_ONES{1'b1}}
   };
   localparam USE_PATTERN_3 = (ROUND == "TRUE") ? "TRUE" : "FALSE";
   // Pattern to be mached can just be all zeros
   localparam [47:0] PATTERN_3 = {48{1'b0}};
   localparam CONVERGENT_RND_MASK_ONES = 48-((26-NBITS)+SCALE_OUT);
   localparam [47:0] MASK_3 = { {CONVERGENT_RND_MASK_ONES{1'b1}},
                                {(48-CONVERGENT_RND_MASK_ONES){1'b0}} };
         
   // The cross map means
   // sample 0 has a systolic 7 and feeds in 1
   // I seriously hope this thing's not an idiot and can remap and merge
   // SRLs as needed. We'll see. If it's dumb we'll push the delay outside
   // and convert everything into like two SRLs or something.
   reg [NBITS-1:0]	  chainA_store0 = {NBITS{1'b0}};
   reg [NBITS-1:0]	  chainA_store1 = {NBITS{1'b0}};
   reg [NBITS-1:0]    chainA_store2 = {NBITS{1'b0}};
   always @(posedge clk_i) begin : CA
      chainA_store0 <= preadd_i;
      chainA_store1 <= chainA_store0;
      chainA_store2 <= chainA_store1;
   end
   
   // 30 bit input 27 bit preadder and save a bit so no saturation
   wire [29:0] dat_pad = { {4{dat_i[NBITS-1]}}, dat_i, { (30-NBITS-4) {1'b0}} };
   wire [26:0] preadd_pad = { chainA_store2[NBITS-1], chainA_store2, {(27-NBITS-1){1'b0}} };
   
   // Each sample is organized as the combination of
   // 2 4-tap systolic filters.
   // We do therefore need to delay the inputs to
   // the second systolic filter.
   wire [47:0] dsp0_to_dsp1;
   wire [29:0] a0_to_a1;	 
   wire [47:0] dsp1_to_dsp2;
   wire [29:0] a1_to_a2;	 
   wire [47:0] dsp2_to_dsp3;
   wire [29:0] a2_to_a3;

   // FIR dsp core lets us connect C to everything even
   // if it's unused, it'll auto-connect the register to the
   // right value.

   // One of the benefits of the fir_dsp_core is that
   // I can connect up something to the pcin port even if
   // it's unused. If you try that with the primitive Vivado
   // complains.
   
   // A systolic MAC wants
   // xi -> |Z| --- |Z| --> xi+1
   //            |
   //          (MULT)
   //            |
   // pi ----->(SUM)-|Z|--> pi+1
   //
   // this puts 2 registers in the cascade path, one in input
   fir_dsp_core #(.ADD_PCIN(CASCADE),
		  .USE_C(USE_C0),
		  .USE_ACIN("FALSE"),
		  .USE_ACOUT("TRUE"),
		  .USE_D("TRUE"),
		  .PREADD_REG(1),
		  .MULT_REG(1),
		  .AREG(1),
		  .ACASCREG(2),
		  .DREG(1),
		  .PREG(1),
		  .CLKTYPE(CLKTYPE))
          u_dsp0( .clk_i(clk_i),
          .rst_i(rst_i),
		  .a_i(dat_pad),
		  .c_i(add_pad),
		  .d_i(preadd_pad),
		  .b_i(coeff0_i),
		  .acout_o(a0_to_a1),
		  .pcin_i(pc_i),
		  .pcout_o(dsp0_to_dsp1));
      
   fir_dsp_core #(.ADD_PCIN("TRUE"),
		  .USE_C(USE_C1),
		  .USE_ACIN("TRUE"),
		  .USE_ACOUT("TRUE"),
		  .USE_D("TRUE"),
		  .PREADD_REG(1),
		  .MULT_REG(1),
		  .AREG(1),
		  .ACASCREG(2),
		  .DREG(1),
		  .PREG(1),
		  .CLKTYPE(CLKTYPE))
          u_dsp1( .clk_i(clk_i),
          .rst_i(rst_i),
		  .acin_i(a0_to_a1),
		  .pcin_i(dsp0_to_dsp1),
		  .c_i(add_pad),
		  .d_i(preadd_pad),
		  .b_i(coeff1_i),
		  .pcout_o(dsp1_to_dsp2),
		  .acout_o(a1_to_a2));	 
   fir_dsp_core #(.ADD_PCIN("TRUE"),
		  .USE_C(USE_C2),
		  .USE_ACIN("TRUE"),
		  .USE_ACOUT("TRUE"),
		  .USE_D("TRUE"),
		  .USE_RND(USE_RND_2),
		  .RND_VAL(RND_CONST),
		  .PREADD_REG(1),
		  .MULT_REG(1),
		  .AREG(1),
		  .ACASCREG(2),
		  .DREG(1),
		  .PREG(1),
		  .CLKTYPE(CLKTYPE))
          u_dsp2( .clk_i(clk_i),
          .rst_i(rst_i),
		  .acin_i(a1_to_a2),
		  .pcin_i(dsp1_to_dsp2),
		  .c_i(add_pad),
		  .d_i(preadd_pad),
		  .b_i(coeff2_i),
		  .pcout_o(dsp2_to_dsp3),
		  .acout_o(a2_to_a3));
   // last core doesn't use the cascade path		  
   wire patdet;
   fir_dsp_core #(.ADD_PCIN("TRUE"),
		  .USE_C(USE_C3),
		  .USE_ACIN("TRUE"),
		  .USE_ACOUT("FALSE"),
		  .USE_D("TRUE"),
		  .USE_RND(USE_RND_3),
		  .RND_VAL(RND_CONST),
		  .USE_PATTERN(USE_PATTERN_3),
		  .PATTERN_VAL(PATTERN_3),
		  .MASK_VAL(MASK_3),
		  .USE_CARRYIN("TRUE"),
		  .PREADD_REG(1),
		  .MULT_REG(1),
		  .AREG(1),
		  .DREG(1),
		  .PREG(1),
		  .CLKTYPE(CLKTYPE))
          u_dsp3( .clk_i(clk_i),
          .rst_i(rst_i),
		  .acin_i(a2_to_a3),
		  .pcin_i(dsp2_to_dsp3),
		  .c_i(add_pad),
		  .d_i(preadd_pad),
		  .b_i(coeff3_i),
		  .carryin_i(1'b1),
		  .p_o(p_o),
		  .pattern_o(patdet),
		  .pcout_o(pc_o)); 

    // the LSB is normally at 26-NBITS, we scale up by SCALE_OUT
    localparam LSB = 26-NBITS+SCALE_OUT;
    assign dat_o[OUTBITS-1:1] = p_o[LSB+1 +: OUTBITS-1];
    assign dat_o[0] = (ROUND == "TRUE") ? p_o[LSB] && !patdet : p_o[LSB];

endmodule // fourtap_systolic_preadd
