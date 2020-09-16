# Synthesizable Verilog modules

* flag_sync.v : Clock-crossing module for single-cycle flags.
* clk_div_ce.v : SRL-based periodic clock CE generator
* async_register.v : Clock-crossing module for a multi-bit register (periodic updates)
* dsp_counter_terminal_count.v : DSP-based counter.
* dsp_delay.v : DSP-based variable delay generation
* dual_prescaled_dsp_scalers.v : Dual 24-bit scalers packed in a DSP with linear prescale.
* dual_dsp_counters.v : Dual 24-bit counter packed in a DSP.
* dsp_macros.vh : Verilog header with macros for DSP usage.
* skidbuffer.v : A generic skid buffer (register slice) for AXI4-Stream.

Note that not all of these are by me (skidbuffer.v), and some
were informed by publically-available ideas but implemented
by me (flag_sync.v).