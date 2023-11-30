# Math related Verilog modules

* ternary_mult23_12.sv : Multiply a 12-bit number by 23 using a ternary add (yes, this seems very specific, it's for a second version of the SW lowpass)
* fast_csa32_adder.v : 3:2 compressor (with output FFs)
* fast_csa53_adder.v : 5:3 compressor (with output FFs)
* fast_csa63_adder.v : 6:3 compressor (with output FFs)
* fast_csa82_adder.v : 8:2 3-stage carry-save adder for bitlengths 3+.

* nr_sqrt.sv : Calculate square root based on non-restoring algorithm.
  Extremely cheap (only requires basically 2x NBIT length registers
  plus a few extra FFs), takes NBIT/2 clocks to finish.
* floorshift_log2.sv : Calculate approximate log2(input) serially
  using the floor-shift method (piecewise linear between powers of 2).
  Also extremely cheap (requires (NBIT+log2(NBIT)+configurable fractional
  number of bits) registers, takes NBIT clocks to finish. Note that
  the algorithm is intrinsically variable-latency, but this module
  fixes the latency to the longest possible.

The fast_csa modules are all examples of carry-save adders, which means
the outputs (called 'sum', 'carry', and 'ccarry') need to be
added together by a ripple-carry adder to get a single value,
with the final value being "sum + (carry<<1) + (ccarry<<2)".
The last adder (fast_csa82_adder) is a combination of 3:2/5:3
compressors in a Wallace tree adder (with a single 6:3 used
to balance logic usage and reduce register count).


