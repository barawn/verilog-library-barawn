`ifndef MGT_VH_
`define MGT_VH_

// Dumb macros to help out with boilerplate.
// This helps killing unused inputs when an IBERT is hooked up
// to Aurora. If you don't explicitly connect some of them they'll
// fail in implementation.
`define UNUSED_GTH_DEBUG_AURORA_PORTS \
   .gt_eyescantrigger(1'b0),          \
   .gt_rxcdrhold(1'b0),               \
   .gt_rxcdrovrden(1'b0),             \
   .gt_rxdfelpmreset(1'b0),           \
   .gt_rxpcsreset(1'b0),              \
   .gt_rxpmareset(1'b0),              \
   .gt_rxbufreset(1'b0),              \
   .gt_pcsrsvdin({16{1'b0}}),         \
   .gt_rxprbscntreset(1'b0),          \
   .gt_rxprbssel(4'h0),               \
   .gt_txinhibit(1'b0),               \
   .gt_txpcsreset(1'b0),              \
   .gt_txpmareset(1'b0),              \
   .gt_txpolarity(1'b0),              \
   .gt_txprbsforceerr(1'b0),          \
   .gt_txprbssel(4'h0)

`endif
