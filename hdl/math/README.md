# Math related Verilog modules

* ternary_mult23_12.sv : Multiply a 12-bit number by 23 using a ternary add (yes, this seems very specific, it's for a second version of the SW lowpass)
* fast_csa32_adder.v : 3:2 compressor (with output FFs)
* fast_csa53_adder.v : 5:3 compressor (with output FFs)
* fast_csa63_adder.v : 6:3 compressor (with output FFs)
* fast_csa82_adder.v : 8:2 3-stage carry-save adder for bitlengths 3+.

* nr_sqrt.sv : Calculate square root based on non-restoring algorithm.
  Extremely cheap (only requires basically 2x NBIT length registers
  plus a few extra FFs), takes NBIT/2 clocks to finish.
* slow_reciprocal.sv : Calculate reciprocal using basic binary long
  division. Takes NBITS clocks, and requires (NBITS+1)*2+1 registers
  plus an SRL+FF. Works up to 32 bits.
* floorshift_log2.sv : Calculate approximate log2(input) serially
  using the floor-shift method (piecewise linear between powers of 2).
  Also extremely cheap (requires (NBIT+log2(NBIT)+configurable fractional
  number of bits) registers, takes NBIT clocks to finish. Note that
  the algorithm is intrinsically variable-latency, but this module
  fixes the latency to the longest possible.
* seven_bit_square.sv : Calculate the square of a 7-bit unsigned number
  in fabric. Small but still not optimal yet.
* signed_8b_square.sv : Calculate the square of an 8-bit signed number
  in fabric. As optimal as it gets without going crazy.
* fivebit_8way_ternary.sv: Add 8 5-bit numbers via ternary adder tree.
* square_5bit_accumulator.sv: Accumulate the squares of 4-bit unsigneds.
  (yes I know it says 5bit, it's 4-bit unsigned).

* xil_tiny_lfsr.sv : tiniest LFSRs you can do
* xil_tiny_lfsr_2bit.sv : generate 2 bits from tiny LFSRs

The fast_csa modules are all examples of carry-save adders, which means
the outputs (called 'sum', 'carry', and 'ccarry') need to be
added together by a ripple-carry adder to get a single value,
with the final value being "sum + (carry<<1) + (ccarry<<2)".
The last adder (fast_csa82_adder) is a combination of 3:2/5:3
compressors in a Wallace tree adder (with a single 6:3 used
to balance logic usage and reduce register count).

The xil_tiny_lfsr modules can provide a variety of LFSRs for
virtually no cost. Because they use SRLs, they take only
2 LUTs and a FF, minimally. The 2-bit version gives you a
2-bit output for almost the same cost as well. The special nature
of these LFSR is that they are generated only from the tail of
the shift registers except for one, so you don't need to tap off
the interior. The one that doesn't use the tails is a 33-bit LFSR
which only needs 1 tap for max length. This one is only available
in single-bit version.