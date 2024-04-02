# Synthesizable Verilog modules

This repository's gotten a little unwieldy, so I'm slowly
trying to reorganize it. This might break a few projects
if you update them until I create management tools.

Files in this directory:

* flag_sync.v : Clock-crossing module for single-cycle flags.
* clk_div_ce.v : SRL-based periodic clock CE generator
* async_register.v : Clock-crossing module for a multi-bit register (periodic updates)
* dsp_counter_terminal_count.v : fsdasggsDSP-based counter.
* dsp_delay.v : DSP-based variable delay generation
* dual_prescaled_dsp_scalers.v : Dual 24-bit scalers packed in a DSP with linear prescale.
* dual_dsp_counters.v : Dual 24-bit counter packed in a DSP.
* dsp_timed_counter.v : 24-bit up-counter that counts for a dynamically programmable interval from a single DSP.
* fir_dsp_core.sv : DSP stripped to its basics for generic FIR filters. Note that additional clever things can be done that this core doesn't support: it's just (a+d)*b + c, with a cascade option, everything constantly clocked and no resets.
* obufds_autoinv.v/ibufds_autoinv.v : utility modules for correctly hooking up differential inputs/outputs via parameter control when the P/Ns might be swapped

* wishbone_arbiter.v : Arbitrate multiple WISHBONE busses based on cyc
* round_robin_arbiter.v : Public-domain round robin arbiter.

* skidbuffer.v : A generic skid buffer (register slice) for AXI4-Stream.
* pps_core.v : External/internal PPS module with external holdoff

* adc_ila_transfer.v : Rescale a full-bandwidth (8 samples/clock) ADC output to 1 sample/clock for input to an ILA using external trigger.

Note that not all of these are by me (skidbuffer.v), and some
were informed by publically-available ideas but implemented
by me (flag_sync.v).

Note: dsp_macros.vh was moved over to the include directory.

## Convenience modules

* wbs_dummy.v : WISHBONE dummy slave module. Always acks, returns 0.
* wbm_dummy.v : WISHBONE dummy master module. Never initiates.
