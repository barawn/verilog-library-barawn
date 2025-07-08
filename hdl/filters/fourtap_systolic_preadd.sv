`timescale 1ns / 1ps

module fourtap_systolic_preadd #( parameter CASCADE = "FALSE",
				  parameter ROUND = "FALSE",
				  localparam NBITS = 12,
				  parameter CLKTYPE = "NONE")(
	    input	  clk_i,
	    input     rst_i,
	    input [NBITS-1:0]  dat_i,
	    input [NBITS-1:0]  preadd_i,
	    input [17:0]  coeff0_i,
	    input [17:0]  coeff1_i,
	    input [17:0]  coeff2_i,
	    input [17:0]  coeff3_i,
	    input [47:0]  pc_i,
	    output [47:0] p_o,
	    input [47:0]  pc_o
      );
   
							         
   // The cross map means
   // sample 0 has a systolic 7 and feeds in 1
   reg [NBITS-1:0]	  chainA_store0 = {NBITS{1'b0}};
   reg [NBITS-1:0]	  chainA_store1 = {NBITS{1'b0}};
   always @(posedge clk_i) begin : CA
      chainA_store0 <= preadd_i;
      chainA_store1 <= chainA_store0;
   end
   
   // 30 bit input 27 bit preadder and save a bit so no saturation
   wire [29:0] dat_pad = { {4{dat_i[NBITS-1]}}, dat_i, { (30-NBITS-4) {1'b0}} };
   wire [26:0] preadd_pad = { chainA_store1[NBITS-1], chainA_store1, {(27-NBITS-1){1'b0}} };
   
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
		  .USE_C("FALSE"),
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
		  .d_i(preadd_pad),
		  .b_i(coeff0_i),
		  .acout_o(a0_to_a1),
		  .pcin_i(pc_i),
		  .pcout_o(dsp0_to_dsp1));
      
   fir_dsp_core #(.ADD_PCIN("TRUE"),
		  .USE_C("FALSE"),
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
		  .d_i(preadd_pad),
		  .b_i(coeff1_i),
		  .pcout_o(dsp1_to_dsp2),
		  .acout_o(a1_to_a2));	 
   fir_dsp_core #(.ADD_PCIN("TRUE"),
		  .USE_C("FALSE"),
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
          u_dsp2( .clk_i(clk_i),
          .rst_i(rst_i),
		  .acin_i(a1_to_a2),
		  .pcin_i(dsp1_to_dsp2),
		  .d_i(preadd_pad),
		  .b_i(coeff2_i),
		  .pcout_o(dsp2_to_dsp3),
		  .acout_o(a2_to_a3));
   fir_dsp_core #(.ADD_PCIN("TRUE"),
		  .USE_C("FALSE"),
		  .USE_ACIN("TRUE"),
		  .USE_ACOUT("FALSE"),
		  .USE_D("TRUE"),
		  .PREADD_REG(1),
		  .MULT_REG(1),
		  .AREG(1),
		  .ACASCREG(2),
		  .DREG(1),
		  .PREG(1),
		  .CLKTYPE(CLKTYPE))
          u_dsp3( .clk_i(clk_i),
          .rst_i(rst_i),
		  .acin_i(a2_to_a3),
		  .pcin_i(dsp2_to_dsp3),
		  .d_i(preadd_pad),
		  .b_i(coeff3_i),
		  .p_o(p_o),
		  .pcout_o(pc_o)); 

endmodule // fourtap_systolic_preadd
