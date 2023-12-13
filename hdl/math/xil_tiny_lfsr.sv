`timescale 1ns / 1ps
// There are a few ultra-tiny LFSRs which can be made
// with Xilinx shift registers and virtually nothing else.
// You basically need an LFSR polynomial with the top and
// bottom bits set in the feedback.
// Then what you do is set up an SRL with the address
// equal to the # of bits minus 1, and register it with a FF.
// Then you take that FF and XOR it with the output of the SRL
// and feed that into your input. That's it: SRL, FF, and LUT.
// This only works for a small number of LFSRs, and only one
// with each length.
// There's also a special-case at 33 bit because you can build
// a max length LFSR with a single tap, and SRL32s give you
// both a tap output and Q31.
//
// I don't have the 3 or 4 bit versions available because they're
// stoooopid.
//
// The *default* LFSR is the ultrahuge one (33 bit) = 8,589,934,591 clocks
// The others can be selected with
// LFSR6  = 63 clocks
// LFSR7  = 127 clocks
// LFSR15 = 32767 clocks
// LFSR22 = 4,194,303 clocks
//
// You can also use LFSR33 for the ultrahuge one.
// Note that you have to hold reset for the number of bits
// of the LFSR for it to actually reset!

// Again, let me stress how utterly ridiculous this is:
//
//      +-----+
//      |SRL32|                     +-------+
// fdbk-|D   Q|---------------------|  LUT O|---fdbk
//      |     |   +------+          |       |
//      |  Q31|---|D FF Q|----+-----|       |
//      +-----+   |      |    |     |       |
//                +------+    |     |       |
//                            |     +-------+
//                            |
//                            +----------------out
// generates a pseudorandom 0/1 bitstream that doesn't repeat
// for 8 BILLION CLOCK CYCLES
// note that START_AFTER_RESET="TRUE" costs you another FF,
// and OUT_BIT="HEAD" also costs you another FF.
//
// AUTOSTART starts the LFSR at GSR exit (at power on)
// START_AFTER_RESET starts the LFSR once rst_i falls
// If START_AFTER_RESET is "FALSE" you need to hook up "start_i"
// if reset is used (or AUTOSTART is TRUE).
module xil_tiny_lfsr #(parameter AUTOSTART = "FALSE",
                       parameter START_AFTER_RESET = "TRUE",
                       parameter LFSR = "LFSR33")(
        input clk_i,
        input ce_i,
        input start_i,
        input rst_i,
        output out_o
    );
    
    reg was_reset = 0;
    reg tail_ff = (AUTOSTART == "TRUE") ? 1'b1 : 1'b0;  
    wire tap;
    wire shift_in = (START_AFTER_RESET == "TRUE") ? 
        (!rst_i) && ((was_reset || start_i) || (tap ^ tail_ff)) :
        (!rst_i) && (start_i || (tap^tail_ff));
    // this will get ignored if START_AFTER_RESET is FALSE
    always @(posedge clk_i) begin
        if (ce_i)
            was_reset <= rst_i;
    end
    generate
        // first handle the SRL16s
        if (LFSR == "LFSR6" ||
            LFSR == "LFSR7" ||
            LFSR == "LFSR15") begin : S
            
            wire [3:0] addr;
            // the length here is #bits - 2
            // because addr counts from 0
            // plus the tail flop
            if (LFSR == "LFSR6") begin : B6
                assign addr = 4'd4;
            end else if (LFSR == "LFSR7") begin : B7
                assign addr = 4'd5;
            end else if (LFSR == "LFSR15") begin : B15
                assign addr = 4'd13;
            end
            
            SRL16E u_srl(.D(shift_in),.CE(ce_i),.CLK(clk_i),
                         .A3(addr[3]),
                         .A2(addr[2]),
                         .A1(addr[1]),
                         .A0(addr[0]),
                         .Q(tap));
            always @(posedge clk_i) begin : TFF
                tail_ff <= tap;
            end
        end
        // next handle the medium-length LFSR (4,194,303)
        else if (LFSR == "LFSR22") begin : M
            SRLC32E u_srl(.D(shift_in),.CE(ce_i),.CLK(clk_i),
                          .A(5'd20),
                          .Q(tap));
            always @(posedge clk_i) begin : TFF
                tail_ff <= tap;
            end                          
        end else begin : L
            // now handle the ultralong case (2^33 - 1)
            wire tail;
            SRLC32E u_srl(.D(shift_in),.CE(ce_i),.CLK(clk_i),
                          .A(5'd19),
                          .Q(tap),
                          .Q31(tail));
            always @(posedge clk_i) begin : TFF
                tail_ff <= tap;
            end
        end
    endgenerate
    
    assign out_o = tail_ff;    
endmodule
