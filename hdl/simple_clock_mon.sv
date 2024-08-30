`timescale 1ns / 1ps
`include "dsp_macros.vh"
// Very, very simple clock monitor. Fairly low resource usage
// for even a fairly large number of clocks. 
//
// TL;DR Usage Version:
// 1) You need a running clock that's relatively fast, probably at least
//    25 MHz ish. 
// 2) You need to calibrate the clock counter first. Write the clock frequency
//    into any counter address. Note that the actual low 8 bits are ignored
//    so if the clock frequency isn't divisible by 256 you might want to round,
//    but the precision is low enough that it almost certainly doesn't matter.
// 3) Read from any address to get the clock count. After you calibrate it
//    you'll need to wait (NUM_CLOCKS*4 ms) before the values are accurate.
//    Which is usually negligibly long anyway.
// 4) The clock frequencies (by default) are measured in steps of 16.384 kHz,
//    however they will read out in Hz correctly: the bottom 14 bits will always
//    be 0. So when you print them out you'll notice that they tend to be quantized
//    in weird values (e.g. 250,003,456 instead of 250 MHz, or 125,009,920 instead
//    of 125 MHz). Intrinsically the values are only 16 bits by default, so if you 
//    want to only store bits [29:14] that captures the entire value anyway.
//    In addition if you want to *disable* that shift so that you just read out
//    a 16 bit value straight, just change CLOCK_SHIFT_DAT to 0.
// 5) You also need to implement CDC constraints, such that
//    going from clk_32x_level -> level_cdc_ff is set to
//    datapath_only with some reasonable value (like 10 ns).

// Having clocks measured to obscene precision is fairly stupid,
// and having them constantly monitored is also pretty dumb.
// For instance, if we have clocks that range from:
// 7.8125 MHz to 500 MHz, this is a total range of 64 (6 bits)
// If we use a 16 bit value to store the count, that means each
// tick is ~15 kHz-ish.
//
// To allow us to count in one clock domain, we'll generate slow
// level changes in the target domain (via the SRL trick) and
// look for rising edges, counting them as 64 ticks.
// In order to get ~15 kHz-ish with 64 tick values that requires
// around 200 Hz-ish accumulating time, around 5 milliseconds.
//
// Of course we want a simple way of getting a value in Hz afterwards
// because EVERYONE ALWAYS complains if software has to do math
// (god only knows why).
// So let's figure out the trick.
// We count in 64 tick values so we'll need to scale up by 64. That's
// easy. We're only going to accumulate for around 1/200th of a second,
// so we would need to multiply by 200, which is awkward. Instead
// make it 1/256th of a second. 1/256th of a second ends up being
// really convenient anyway since lots of clocks are evenly divisible
// at 256ths of a second.
// So for instance if we have a 40 MHz clock, 1/256th of a second
// consists of 156,250 ticks.
//
// To really simplify things, we put the burden on software to
// calibrate the initialization clock. We use the dsp_timed_counter
// module to get us a programmable interval to write into, and
// shift the written value as input to it.
//
// Resource-wise this is a very compact clock monitor. Each clock
// needs an SRL16+FF as a divider, and then 3x FFs for the CDC transfer.
// Then the distributed RAM + FFs used for the clock storage and a single DSP.
// That's it.
//
// CLOCK_BITS/CLOCK_SHIFT_CNT/CLOCK_SHIFT_DAT can be adjusted for more precision but it's
// basically pointless, it's easier to leave them as they are unless
// you've got super-huge resource constraints or something.
//
// Basically the value that you read is
// (((24-bit DSP output) >> CLOCK_SHIFT_CNT) % (1<<CLOCK_BITS)) << CLOCK_SHIFT_DAT.
//
// Because the clock cross is formed by a 32-fold divide,
// this means that your base clock needs to be probably at most 30x slower than
// the fastest clock. This shouldn't be an issue in most cases: the highest
// clock we can really run at is 500 MHz ish, which would be like, 16 MHz.
// Our init clock here is 40 MHz.
//
// Note: you CANNOT read back the interval. It's internal to the DSP.
// Deal with it.
//
// Note that clk_running_o is also a status bit in the clk_i domain
// as to whether or not that clock is active. This is essentially a completely
// separate system so if you don't use that, it'll get trimmed entirely.
// It creates a separate interval counter based on the interface clock
// to monitor clocks up to 1/64th the interface clock's speed.
module simple_clock_mon #(
        parameter NUM_CLOCKS = 8,       // Number of clocks to monitor
        parameter CLOCK_BITS = 16,      // Precision to store. Can be up to 24
        parameter CLOCK_SHIFT_CNT = 0,  // Number of bits to shift DSP output *down*
        parameter CLOCK_SHIFT_DAT = 14  // Number of bits to upshift the output.
    )(
        input clk_i,
        input [$clog2(NUM_CLOCKS)-1:0] adr_i,
        input en_i,
        input wr_i,
        input [31:0] dat_i,
        output [31:0] dat_o,
        output ack_o,
        output [NUM_CLOCKS-1:0] clk_running_o,
        
        input [NUM_CLOCKS-1:0] clk_mon_i
    );
    
    // Number of bits for the clock select counter.
    localparam SELECT_BITS = $clog2(NUM_CLOCKS);
    // Number of clocks, expanded to nearest power of 2. For memory storage.
    localparam NUM_CLOCKS_EXP = (1<<SELECT_BITS);
    
    // Memory storage for the clock outputs. Will get implemented as dual-port dist RAM
    // I hope.
    reg [CLOCK_BITS-1:0] clk_count_value[NUM_CLOCKS_EXP-1:0];
    // Output data register
    reg [CLOCK_BITS-1:0] clk_value_read = {CLOCK_BITS{1'b0}};
    // Initialize all values to zero (including unused ones in the expanded space).
    integer ii;
    initial for (ii=0;ii<NUM_CLOCKS_EXP;ii=ii+1) clk_count_value[ii] <= {CLOCK_BITS{1'b0}};
    
    // These are the level toggles for each clock. They toggle every 32 clocks.
    reg [NUM_CLOCKS-1:0] clk_32x_level = {NUM_CLOCKS{1'b0}};
    
    // We need 3 registers here: the first is the metastable
    // clock crossing register, and the next two form the
    // rising edge detector. We can't (well, shouldn't) just
    // do (ff1 && !ff2) because the timing tools would think
    // they have a full clock to get there.
    (* ASYNC_REG = "TRUE" *)
    reg [NUM_CLOCKS-1:0] level_cdc_ff1 = {NUM_CLOCKS{1'b0}};
    (* ASYNC_REG = "TRUE" *)
    reg [NUM_CLOCKS-1:0] level_cdc_ff2 = {NUM_CLOCKS{1'b0}};
    (* ASYNC_REG = "TRUE" *)
    reg [NUM_CLOCKS-1:0] level_cdc_ff3 = {NUM_CLOCKS{1'b0}};
    // This is the actual rising edge for each flag.
    reg [NUM_CLOCKS-1:0] level_flag = {NUM_CLOCKS{1'b0}};

    reg [SELECT_BITS-1:0] clock_select = {SELECT_BITS{1'b0}};
    wire selected_clock_cnt64 = level_flag[clock_select];
    
    // Clock running subsystem.
    wire clk_running_will_reset;
    reg clk_running_reset = 0;
    clk_div_ce #(.EXTRA_DIV2("TRUE")) u_clk_run_timer(.clk(clk_i),.ce(clk_running_will_reset));
    always @(posedge clk_i) clk_running_reset <= clk_running_will_reset;
    wire [NUM_CLOCKS-1:0] clk_running_status;
    reg [NUM_CLOCKS-1:0] clk_running_status_cdc1 = {NUM_CLOCKS{1'b0}};
    reg [NUM_CLOCKS-1:0] clk_running_status_cdc2 = {NUM_CLOCKS{1'b0}};
    // Implement the level toggles/clock monitors
    generate
        genvar i;
        for (i=0;i<NUM_CLOCKS;i=i+1) begin : CLG
            reg q_rereg = 0;
            wire srl_out;
            SRLC32E #(.INIT(32'h0)) u_srl(.D(!srl_out),.CE(1'b1),.Q31(srl_out),.CLK(clk_mon_i[i]));
            always @(posedge clk_mon_i[i]) clk_32x_level[i] <= srl_out;
            FDCE #(.INIT(1'b0))
                u_clkmon(.D(1),.CE(1),.C(clk_mon_i[i]),.CLR(clk_running_reset),.Q(clk_running_status[i]));              
        end
    endgenerate

    always @(posedge clk_i) begin
        level_cdc_ff1 <= clk_32x_level;
        level_cdc_ff2 <= level_cdc_ff1;
        level_cdc_ff3 <= level_cdc_ff2;
        // Form the rising edges.
        level_flag <= ~level_cdc_ff3 & level_cdc_ff2;
        clk_running_status_cdc1 <= clk_running_status;
        // If a clock is continually running and is running faster than ~1/64th clk_i
        // (which is probably pretty low if clk_i is in the neighborhood of 10-100 MHz)
        // this should stay 1.
        if (clk_running_will_reset) clk_running_status_cdc2 <= clk_running_status_cdc1;
    end            

    // use the DSP timed counter module.
    wire [24:0] count_out;
    wire        count_done;
    dsp_timed_counter u_counter( .clk( clk_i ),
                                 .count_in( selected_clock_cnt64 ),
                                 // Grab the top 24 bits of dat_i to
                                 // accomplish the divide by 256.
                                 // So if you write in 40,000,000 (0x2625A00)
                                 // you're actually writing in 156250 (0x2625A)
                                 .interval_in( dat_i[8 +: 24] ),
                                 .interval_load( en_i && wr_i && ack_o ),
                                 .count_out( count_out ),
                                 .count_out_valid( count_done ));
                      
    reg ack_ff = 0;
                      
    always @(posedge clk_i) begin
        if (count_done) clk_count_value[clock_select] <= count_out[ CLOCK_SHIFT_CNT +: CLOCK_BITS];
        if (en_i && !wr_i) clk_value_read <= clk_count_value[adr_i];
        ack_ff <= en_i;
        
        if (count_done) begin
            if (clock_select == (NUM_CLOCKS-1)) clock_select <= {SELECT_BITS{1'b0}};
            else clock_select <= clock_select + 1;
        end
    end

    assign ack_o = ack_ff && en_i;
    assign dat_o = { {(CLOCK_BITS-CLOCK_SHIFT_DAT){1'b0}}, clk_value_read, {CLOCK_SHIFT_DAT{1'b0}}};

    assign clk_running_o = clk_running_status_cdc2;
endmodule
