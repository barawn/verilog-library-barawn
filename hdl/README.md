# Synthesizable Verilog modules

* flag_sync.v : Clock-crossing module for single-cycle flags.
* clk_div_ce.v : SRL-based periodic clock CE generator
* async_register.v : Clock-crossing module for a multi-bit register (periodic updates)
* dsp_counter_terminal_count.v : DSP-based counter.
* dsp_delay.v : DSP-based variable delay generation
* dual_prescaled_dsp_scalers.v : Dual 24-bit scalers packed in a DSP with linear prescale.
* dual_dsp_counters.v : Dual 24-bit counter packed in a DSP.

* skidbuffer.v : A generic skid buffer (register slice) for AXI4-Stream.
* pps_core.v : External/internal PPS module with external holdoff

* adc_ila_transfer.v : Rescale a full-bandwidth (8 samples/clock) ADC output to 1 sample/clock for input to an ILA using external trigger.

* fast_csa32_adder.v : 3:2 compressor (with output FFs)
* fast_csa53_adder.v : 5:3 compressor (with output FFs)
* fast_csa63_adder.v : 6:3 compressor (with output FFs)
* fast_csa82_adder.v : 8:2 3-stage carry-save adder for bitlengths 3+.

The last three are all examples of carry-save adders, which means
the outputs (called 'sum', 'carry', and 'ccarry') need to be
added together by a ripple-carry adder to get a single value,
with the final value being "sum + (carry<<1) + (ccarry<<2)".
The last adder (fast_csa82_adder) is a combination of 3:2/5:3
compressors in a Wallace tree adder (with a single 6:3 used
to balance logic usage and reduce register count).

Note that not all of these are by me (skidbuffer.v), and some
were informed by publically-available ideas but implemented
by me (flag_sync.v).

Note: dsp_macros.vh was moved over to the include directory.

## Convenience modules

* wbs_dummy.v : WISHBONE dummy slave module. Always acks, returns 0.
* wbm_dummy.v : WISHBONE dummy master module. Never initiates.
