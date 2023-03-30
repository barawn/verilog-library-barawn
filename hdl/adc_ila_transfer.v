`timescale 1ns / 1ps
// This module allows you to pipe an ADC channel (8 samples/1 clock) into an ILA and actually use
// the waveform feature. It does this by collecting the stream at a trigger and resizing it.
//
// adc_out/adc_valid need to go to the ILA. Configure the ILA to have a "trigger out" port!!
// 2 ports, 1 with a 12-bit width (adc_out), 1 with a single-bit width (adc_valid).
// The adc_out input port should be DATA ONLY.
// Then hook up trig_out to trigger_in, and trigger_ack to trig_ack.
// Also configure "Capture Control" enabled.
//
// You need to create 2 IP cores. I don't include the XCIs here because that will lock you to
// a specific Vivado IP version.
//
// adc_ila_fifo : FIFO Generator, Native mode, common clock builtin FIFO, 96 bits, 512 depth, first-word fall through, valid flag enabled (all else default)
// adc_ila_widthconv : AXI4-Stream Data Width Converter, slave interface 16 bytes, master interface 2 bytes (everything else default)
//
// Then when you want to *use* this: MAKE SURE THE ILA IS IN TRIGGER OUTPUT MODE (it starts up as DISABLED)
// Then just trigger on "adc_valid" being 0 or something. Doesn't matter, you're forcing a trigger to occur.
// Also set up the capture to only acquire when adc_valid = 1.
//
// If you need to *trigger* on the ADC stream, that's harder, but not impossible. You need to add 8 additional
// TRIGGER-ONLY input ports to the ILA (12-bits) and turn the 128-bit output into 8x 12-bit inputs
// (grabbing the high 12 bits of every 16 bit word). Feed those 8x inputs into the trigger only input ports of
// the ADC. Now in Hardware Manager, configure those 8 samples to each have their own identical trigger with a giant OR of all of them.
// there's your trigger.
// Awkward, horrible, but that's what it is.
module adc_ila_transfer(
        input [127:0] adc_in,
        input adc_clk,
        input trigger_in,
        output trigger_ack,
        output [11:0] adc_out,
        output        adc_valid
    );

    parameter DEBUG = "FALSE";
    
    // just shove 128 samples in
    reg [7:0] sample_counter = {8{1'b0}};
    reg        sampling = 0;
    // and now count the samples into the ILA...
    reg [10:0] transfer_counter = {11{1'b0}};
    reg        transferring = 0;
    reg        transferring_rereg = 0;
    
    // and count the reset time
    reg        waiting = 0;
    reg [5:0] waiting_counter = {6{1'b0}};

    reg        holdoff = 0;
    reg        trigger_in_rereg = 0;
                
    always @(posedge adc_clk) begin
        if (sample_counter[7]) sampling <= 1'b0;
        else if (trigger_in && !holdoff) sampling <= 1'b1;
        
        if (trigger_in) holdoff <= 1;
        else if (!trigger_in && trigger_in_rereg) holdoff <= 0;
        
        trigger_in_rereg <= trigger_in;
        
        // Transfer actually starts *before* transferring goes high.
        // But we know transferring can't *end* until sampling ends.
        // So "sampling" is really "sampling & transferring"
        // and "transferring" is really "only transferring"
        if (sample_counter[7]) transferring <= 1'b1;
        else if (transfer_counter[10]) transferring <= 1'b0;
        transferring_rereg <= transferring;
                        
        if (transfer_counter[10]) waiting <= 1'b1;
        else if (waiting_counter[5]) waiting <= 1'b0;
        
        if (sampling) sample_counter <= sample_counter[6:0] + 1;
        else sample_counter <= {8{1'b0}};
        
        if (adc_valid) transfer_counter <= transfer_counter[9:0] + 1;
        else if (!transferring && transferring_rereg) transfer_counter <= {11{1'b0}};
        
        if (waiting) waiting_counter <= waiting_counter[4:0] + 1;
        else waiting_counter <= {6{1'b0}};                        
    end 
    
    // rewire the 128 bits into 96 bits
    wire [95:0] data_in;
    // and remap the output 96 bits back into 128 to go into the width converter
    wire [95:0] data_out;
    wire        data_valid;
    wire        data_read;
    wire [127:0] adc_fifo_tdata;
    wire         adc_fifo_tvalid = data_valid;
    wire         adc_fifo_tready;
    assign data_read = adc_fifo_tvalid && adc_fifo_tready;
    
    wire [15:0]  adc_tdata;
    wire         adc_tvalid;
    wire         adc_tready = 1'b1;
    // out of the width converter
    generate
        genvar i;
        for (i=0;i<8;i=i+1) begin : REMAP
            assign data_in[12*i +: 12] = adc_in[(16*i + 4) +: 12];
            assign adc_fifo_tdata[16*i +: 16] = { data_out[12*i +: 12], 4'b0000 };
        end
    endgenerate
    
    adc_ila_fifo u_fifo(.clk(adc_clk),
                        .din(data_in),
                        .wr_en(sampling),
                        .srst(waiting_counter[3]),
                        .dout(data_out),
                        .rd_en(data_read),
                        .valid(data_valid));
    adc_ila_widthconv u_widthconv(.aclk(adc_clk),
                                  .aresetn(1'b1),
                                  .s_axis_tdata(adc_fifo_tdata),
                                  .s_axis_tvalid(adc_fifo_tvalid),
                                  .s_axis_tready(adc_fifo_tready),
                                  .m_axis_tdata(adc_tdata),
                                  .m_axis_tvalid(adc_tvalid),
                                  .m_axis_tready(adc_tready));
                                  
    assign adc_out = adc_tdata[4 +: 12];
    assign adc_valid = adc_tvalid;
    assign trigger_ack = waiting_counter[5];                                  
        
    
endmodule
