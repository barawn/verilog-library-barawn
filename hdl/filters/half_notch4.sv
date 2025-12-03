`timescale 1ns / 1ps

// Halfband notch. This implements a notch roughly
// 50 MHz wide centered 
module half_notch4 #(parameter NBITS=12,
		     localparam NSAMP=4)
   ( input clk_i,
     input [NBITS*NSAMP-1:0]  dat_i,
     output [NBITS*NSAMP-1:0] dat_o );

   // We need to generate a 13 clock delay to feed into the
   // pre-adder.
   localparam [4:0] PREADD_DELAY = 5'd12;
   wire [NBITS*NSAMP-1:0]     dat_delay;
   distram14_delay #(.NBITS(12),
		     .NSAMP(4),
		     .DELAY(PREADD_DELAY)) u_delay(.clk_i(clk_i),
					    .rst_i(1'b0),
					    .dat_i(dat_i),
					    .dat_o(dat_delay));
   // let's just try ONE of them
   generate
      genvar		      i;
      for (i=0;i<NSAMP;i=i+1) begin : SS
	 // The filter splits into positive and negative portions
	 // thanks to the fact that it's centered at half-band.
	 // Positive in is the sample + 2.
	 wire [11:0] pos_in = dat_i[NBITS*((i+2)%4) +: NBITS];
	 wire [11:0] pos_delay = dat_delay[NBITS*((i+2)%4) +: NBITS];
	 wire [12:0] pos_out;
	 
	 wire [11:0] neg_in = dat_i[NBITS*i +: NBITS];
	 reg [11:0] neg_delay = {12{1'b0}};
	 always @(posedge clk_i) begin : ND
	   neg_delay <= dat_delay[NBITS*i +: NBITS];
	 end
	 wire [47:0] pos_p_out;
	 wire [47:0] neg_pc_out;
	 wire [29:0] neg_ac_out;
	 wire [47:0] completion_out;
	 seventap_systolic_preadd #(.PREADD_REG(0))
	   u_pos(.clk_i(clk_i),
		 .rst_i(1'b0),
		 .dat_i(pos_in),
		 .preadd_i(pos_delay),
		 .coeff0_i(18'd151),
		 .coeff1_i(18'd340),
		 .coeff2_i(18'd551),
		 .coeff3_i(18'd761),
		 .coeff4_i(18'd947),
		 .coeff5_i(18'd1086),
		 .coeff6_i(18'd1160),
		 .p_o(pos_p_out),
		 .dat_o(pos_out));
     // The negative chain is similar. We're leaving off the last tap
     // because it's going to be used for combining with the other
     // input. We sadly can't bypass the multiplier even though it isn't
     // a multiplier because the scaling is wrong.
     seventap_systolic_preadd #(.PREADD_REG(0),.ACASCOUT("TRUE"))
        u_neg(.clk_i(clk_i),
              .rst_i(1'b0),
              .dat_i(neg_in),
              .preadd_i(neg_delay),
              .coeff0_i(-18'd70),
              .coeff1_i(-18'd241),
              .coeff2_i(-18'd444),
              .coeff3_i(-18'd657),
              .coeff4_i(-18'd858),
              .coeff5_i(-18'd1023),
              .coeff6_i(-18'd1133),
              .ac_o(neg_ac_out),
              .pc_o(neg_pc_out),
              .dat_o(neg_out));
     // The completion then handles the rounding and saturation detection.
     // We need to downshift the data by 14.
     localparam PARAMETER_SCALE = 14;
     localparam CONVERGENT_RND_ONES = (26-NBITS+PARAMETER_SCALE-1);
     localparam [47:0] RND_CONST = { {(48-CONVERGENT_RND_ONES){1'b0}}, {CONVERGENT_RND_ONES{1'b1}} };
     localparam [47:0] PATTERN_MATCH = {48{1'b0}};
     localparam CONVERGENT_RND_MASK_ONES = 48 - ((26-NBITS)+PARAMETER_SCALE);
     localparam [47:0] PATTERN_MASK = { {CONVERGENT_RND_MASK_ONES{1'b1}}, {(48-CONVERGENT_RND_MASK_ONES){1'b0}} };
     localparam LSB = 26 - NBITS+PARAMETER_SCALE;
     wire patdet;
     fir_dsp_core #(.ADD_PCIN("TRUE"),
                    .USE_ACIN("TRUE"),
                    .USE_C("TRUE"),
                    .USE_CARRYIN("TRUE"),
                    .PREADD_REG(0),
                    .MULT_REG(1),
                    .USE_D("FALSE"))
        u_completion(.clk_i(clk_i),
                     .rst_i(1'b0),
                     .acin_i(neg_ac_out),
                     .pcin_i(neg_pc_out),
                     .b_i(18'd16384),
                     .c_i(pos_p_out),
                     .carryin_i(1'b1),
                     .pattern_o(patdet),
                     .p_o(completion_out));
     assign dat_o[11:1] = completion_out[LSB+1 +: 11];
     assign dat_o[0] = completion_out[LSB];
      end
   endgenerate
   
endmodule // half_notch4

		   
