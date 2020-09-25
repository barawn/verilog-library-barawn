// Adapter for reset for a 7-series FIFO.
// FIFO resets are technically asynchronous,
// but they're actually internally synchronized
// for 7-series. The only issue is that the
// release is asynchronous AND some of the
// goddamn helper shit is asynchronous.
// So we hold everything slightly longer.
//
// areset doesn't have to be long, but
// multiple aresets CANNOT happen in less than 5 clocks.
//
// just do
// s_axis_tready = !fifo_full && !rst_busy
// wr_en = s_axis_tready && s_axis_tvalid
// m_axis_tvalid = fifo_valid && !rst_busy
// rd_en = m_axis_tready && m_axis_tvalid
//
// Valid needs to be guarded because the FIFO Generator's
// valid output is asynchronously set by the reset. With
// this logic it's both the assertion/deassertion of
// all AXI4-Stream signals are completely synchronous
// to the clock.
//
// Don't use 7-series FIFOs for AXI4-Stream
// in independent clocks. It's just a pain.
`timescale 1ns/1ps
module bfifo_srst( input aclk,
		   input  aresetn,
		   output fifo_rst,
		   output rst_busy );
   // this does
   // clk aresetn do_reset do_reset_delay fifo_in_rst fifo_rst rst_busy
   // 0   1       0        00000          0           0        0
   // 1   0       0        00000          0           0        1
   // 2   1       1        00000          1           1        1
   // 3   1       1        00001          1           1        1
   // 4   1       1        00010          1           1        1
   // 5   1       1        00100          1           1        1
   // 6   1       1        01000          1           1        1
   // 7   1       1        10000          1           0        1
   // 8   1       0        00000          0           0        0
   
   reg 			  areset_rereg = 0;   
   reg 			  do_reset = 0;
   reg [4:0] 		  do_reset_delay = {5{1'b0}};
   reg 			  fifo_in_rst = 0;   
   always @(posedge aclk) begin
      areset_rereg <= !aresetn;
      do_reset <= !aresetn && areset_rereg;
      do_reset_delay <= { do_reset_delay[3:0], do_reset };
      if (!aresetn && areset_rereg) fifo_in_rst <= 1;
      else if (do_reset_delay[4]) fifo_in_rst <= 0;
   end
   assign rst_busy = (!aresetn || fifo_in_rst);
   assign fifo_rst = (fifo_in_rst && !do_reset_delay[4])
   
endmodule // bfifo_srst
