# Math related Verilog modules

* ternary_mult23_12.sv : Multiply a 12-bit number by 23 using a ternary add (yes, this seems very specific, it's for a second version of the SW lowpass)
* fast_csa32_adder.v : 3:2 compressor (with output FFs)
* fast_csa53_adder.v : 5:3 compressor (with output FFs)
* fast_csa63_adder.v : 6:3 compressor (with output FFs)
* fast_csa82_adder.v : 8:2 3-stage carry-save adder for bitlengths 3+.
* 

The fast_csa modules are all examples of carry-save adders, which means
the outputs (called 'sum', 'carry', and 'ccarry') need to be
added together by a ripple-carry adder to get a single value,
with the final value being "sum + (carry<<1) + (ccarry<<2)".
The last adder (fast_csa82_adder) is a combination of 3:2/5:3
compressors in a Wallace tree adder (with a single 6:3 used
to balance logic usage and reduce register count).


