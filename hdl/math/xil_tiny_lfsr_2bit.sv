`timescale 1ns / 1ps
// This is based on the xil_tiny_lfsr module, but
// I don't use it here. Specifically this version
// generates a *2 bit* LFSR using 2x SRL16s. As in,
// it generates 2 bits per clock.
//
// The reason this is cool is that the SRL16s
// are actually configured *identically* so
// they *completely combine*.
//
// There are 4 different options.
// Because you step 2 at a time and LFSRs all have odd
// period, in the "technical" (2^nbits-1) period
// you actually output the sequence twice, just with
// the bits delayed and swapped. But this still kinda
// looks random-y anyway.
//
// LFSR6 = 63       clocks
// LFSR7 = 127      clocks
// LFSR15 = 32767   clocks
// LFSR22 = 4,194,303 clocks
//
// Note also that LFSR7/15 technically have their two
// bits offset in time, but this isn't really a big deal. 
//
// Note that you can't really do this trick for LFSR33 easily
// because you'd need 2x 16 tap SRLs, but you don't get the
// second output you need in that case. So you'd actually
// need 4 SRLs. 
// You actually can get the same thing from a 65-bit LFSR,
// I think, which has taps at 65/47.
module xil_tiny_lfsr_2bit #(parameter LFSR = "LFSR22",
                            parameter AUTOSTART = "FALSE",
                            parameter START_AFTER_RESET = "TRUE")(
        input clk_i,
        input rst_i,
        input start_i,
        output [1:0] out_o
    );
    
    reg was_reset = 0;
    
    reg [1:0] tail_ff = (AUTOSTART == "TRUE") ? 2'b01 : 2'b00;
    // we don't call these tap
    wire [1:0] srl_xor;
    wire [1:0] shift_in;
    
    // this goes 1:0 b/c the second SRL is 'older'
    assign shift_in[1] = (START_AFTER_RESET == "TRUE") ? 
        (!rst_i) && ((was_reset || start_i) || srl_xor[1]) :
        (!rst_i) && (start_i || srl_xor[1]);
    assign shift_in[0] = !rst_i && srl_xor[0];
            
    generate
        wire [3:0] addr;
        wire [1:0] tap;
        if (LFSR == "LFSR6") begin : L6
            // 6-bit LFSR needs 2x length 2 shift regs 
            assign addr = 4'd1;
            // and since it's even, srl_xor[1] is tail_ff[1] ^ tail_ff[0]
            assign srl_xor[1] = tail_ff[1] ^ tail_ff[0];
            // and the other is tail_ff[0] ^ tap[1]
            assign srl_xor[0] = tail_ff[0] ^ tap[1];
        end else if (LFSR == "LFSR7") begin : L7
            // 7 bit LFSR needs 2x length 3 shift regs
            assign addr = 4'd2;
            // since it's odd, srl_xor[1] is tail_ff[0] ^ tap[1]
            assign srl_xor[1] = tail_ff[0] ^ tap[1];
            // and the other is tap[1] ^ tap[0]
            assign srl_xor[0] = tap[1] ^ tap[0];
        end else if (LFSR == "LFSR15") begin : L15
            // 15-bit LFSR needs 2x length 7 shift regs
            assign addr = 4'd6;
            // since it's odd, srl_xor[1] is tail_ff[0] ^ tap[1]
            assign srl_xor[1] = tail_ff[0] ^ tap[1];
            // and the other is tap[1] ^ tap[0]
            assign srl_xor[0] = tap[1] ^ tap[0];
        end else if (LFSR == "LFSR22") begin : L22
            // 22-bit LFSR needs 2x length 10 shift regs
            assign addr = 4'd10;
            // and since it's even, srl_xor[1] is tail_ff[1] ^ tail_ff[0]
            assign srl_xor[1] = tail_ff[1] ^ tail_ff[0];
            // and the other is tail_ff[0] ^ tap[1]
            assign srl_xor[0] = tail_ff[0] ^ tap[1];
        end
        SRL16E u_srl0(.D(shift_in[0]),.CLK(clk_i),
                      .A3(addr[3]),
                      .A2(addr[2]),
                      .A1(addr[1]),
                      .A0(addr[0]),
                      .Q(tap[0]));
        SRL16E u_srl1(.D(shift_in[1]),.CLK(clk_i),
                      .A3(addr[3]),
                      .A2(addr[2]),
                      .A1(addr[1]),
                      .A0(addr[0]),
                      .Q(tap[1]));
        always @(posedge clk_i) begin : TFF
            tail_ff[0] <= tap[0];
            tail_ff[1] <= tap[1];
        end
    endgenerate

    assign out_o = tail_ff;
endmodule
