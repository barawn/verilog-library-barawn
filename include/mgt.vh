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

// For GTP transceivers there's no in-system IBERT module
// (jerks). But we can still pick off the ports the vast
// majority of people won't use.
`DEFINE UNUSED_GTP_DEBUG_AURORA_PORTS \
  .gt0_txchardispmode_in(2'b00),      \
  .gt0_txchardispval_in(2'b00),       \
  .gt0_txmaincursor_in(7'b0000000),   \
  .gt0_txpolarity_in(1'b0),           \
  .gt0_rxlpmhfhold_in(1'b0),          \
  .gt0_rxlpmlfhold_in(1'b0),          \
  .gt0_rxlpmreset_in(1'b0),           \
  .gt0_rxlpmhfovrden_in(1'b0),        \
  .gt0_rxcdrhold_in(1'b0),            \
  .gt0_eyescanreset_in(1'b0),         \
  .gt0_eyescantrigger_in(1'b0),       \
  .gt0_rxprbssel_in(3'b000),          \
  .gt0_rxprbscntreset_in(1'b0),       \
  .gt0_rxpcsreset_in(1'b0),           \
  .gt0_rxpmareset_in(1'b0),           \
  .gt0_rxbufreset_in(1'b0),           \
  .gt0_txprbsforceerr_in(1'b0),       \
  .gt0_txprbssel_in(3'b000),          \
  .gt0_txpcsreset_in(1'b0),           \
  .gt0_txinhibit_in(1'b0),            \
  .gt0_txpmareset_in(1'b0)

`endif
