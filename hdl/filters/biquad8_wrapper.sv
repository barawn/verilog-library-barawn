`timescale 1ns /1ps
`include "interfaces.vh"

// this is a WISHBONE wrapper for the biquads
// to allow the control interface to be in a different
// domain.
// we have 16 of these guys so we peel off lots of the
// space and just make this 7 bits
module biquad8_wrapper #(parameter NBITS=16, // input number of bits
			 parameter NFRAC=2,  // input number of fractional bits
			 parameter NSAMP=8,  // number of samples
			 parameter OUTBITS=16, // output scaling
			 parameter OUTFRAC=2)
   (    
    // wishbone side
    input		       wb_clk_i,
    input		       wb_rst_i,
			       `TARGET_NAMED_PORTS_WB_IF( wb_ , 7, 32),
    
    // data side
    input		       clk,
    // leave this here to allow for updating everyone at the same time
    input		       global_update_i,
    input [NBITS*NSAMP-1:0]    dat_i,
    output [OUTBITS*NSAMP-1:0] dat_o
    );

   parameter		       WBCLKTYPE = "PSCLK";
   parameter		       CLKTYPE = "ACLK";
     
   
   `define ADDR_MATCH( in, val) (in[7:2] == val[7:2])
   
   reg			       pending = 0;
   reg			       pending_rereg = 0;

   (* CUSTOM_CC_SRC = WBCLKTYPE *)
   reg [17:0]		       coeff_hold = {18{1'b0}};
   (* CUSTOM_CC_SRC = WBCLKTYPE *)
   reg			       coeff_wr_hold = 0;
   (* CUSTOM_CC_DST = CLKTYPE *)
   reg			       coeff_wr = 0;   

   wire			       wr_wbclk = pending && !pending_rereg;   
   wire			       wr_clk;
   flag_sync u_wrsync(.in_clkA(wr_wbclk),.out_clkB(wr_clk),.clkA(wb_clk_i),.clkB(clk_i));
   
   reg			       ack_clk = 0;
   wire			       ack_wbclk;
   flag_sync u_acksync(.in_clkA(ack_clk),.out_clkB(ack_wbclk),.clkA(clk_i),.clkB(wb_clk_i));
      
   reg			       update_wbclk = 0;   
   wire			       update_clk;   
   reg			       update = 0;

   reg			       read_ack = 0;
   
   
   always @(posedge wb_clk_i) begin
      read_ack = (wb_cyc_i && wb_stb_i && !wb_we_i);
      
      if (ack_wbclk || wb_rst_i)
	pending <= 0;
      else if (wb_cyc_i && wb_stb_i && wb_we_i)
	pending <= 1;

      pending_rereg <= pending;      

      update_wbclk <= global_update_i || (pending && !pending_rereg && `ADDR_MATCH(wb_adr_i, 7'h00) && wb_sel_i[0] && wb_dat_i[0]);
            
      if (wb_cyc_i && wb_stb_i && wb_we_i) begin
	 if (`ADDR_MATCH(wb_adr_i, 7'h04)) begin
	    coeff_hold <= wb_dat_i[17:0];
            coeff_wr_hold <= 1;
	 end else begin
	    coeff_wr_hold <= 0;
	 end	 
      end	 
   end

   always @(posedge clk_i) begin
      ack_clk <= wr_clk;
      update <= update_clk;
      coeff_wr <= wr_clk && coeff_wr_hold;      
   end   
   
   assign wb_ack_o = ((ack_wbclk && pending) || read_ack) && wb_cyc_i;

   biquad8_single_zero_fir #(.NBITS(NBITS),.NFRAC(NFRAC),
			     .NSAMP(NSAMP),.OUTBITS(OUTBITS),
			     .OUTFRAC(OUTFRAC))
   u_fir(.clk(clk_i),
	 .dat_i(dat_i),
	 .coeff_dat_i(coeff_hold),
	 .coeff_wr_i(coeff_wr),
	 .coeff_update_i(update),
	 .dat_o(dat_o));
   
endmodule
    
			 
