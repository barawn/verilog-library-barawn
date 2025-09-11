`timescale 1ns / 1ps
`include "dsp_macros.vh"

// (C) Patrick Allison (allison.122@osu.edu) or the Ohio State University.
// Please contact me either directly or via GitHub for reuse purposes.

// The DSPs are arranged in a chain of 4, which means we don't need
// an address at all, it's just a single write value.
//
// We have *2* clocks to deal with this. Which is a bit challenging.
// Fundamentally we have
// y0    | A     B | | y0[-2] |   | y0_fir_in |
//    =  |         | |        | + |           |
// y1    | C     D | | y1[-2] |   | y1_fir_in |
//
// So what we do is do
// dsp0       dsp1       dsp2       dsp3
// y0_dspA -> y0_dspB -> y1_dspA -> y1_dspB
//
//
// WHAT WE HAVE TRIED THAT DOESN'T WORK:
// 1) Straightforward option: connect dsp1/3->dsp0/2, no Areg, connect dsp3/1->dsp1/2 with Areg.
//
// However, we can see that we *can* get to the multiplier fairly easily!
// So what we do is instead of the Preg in DSP0/2, we put the *MREG* there.
// This balances the delay a bit better.
// In the first case:
// dsp1 -> dsp0   arrival at 7.592 ns
// dsp0 -> dsp1   arrival at 6.040 ns
//
// This has *dramatically* unbalanced delays.
//
// So obviously if we put the MREG it arrives at 6.834 ns, with slack of 0.7 ns.
// And then it adds 0.758 to the other, arriving at 6.798, still with slack of 0.7 ns.
//
// So this is a useful note for the future: you *can* add through 2 DSPs in one clock, easily.
module biquad8_pole_iir #(parameter NBITS=24, 
			  parameter NFRAC=10, 
			  parameter CLKTYPE = "NONE")(
        input clk,	
        input rst,
	
        input [17:0] coeff_dat_i,
        input coeff_wr_i,
        input coeff_update_i,
        
        input [47:0] y0_fir_in,
        input [47:0] y1_fir_in,
        output [NBITS-1:0] y0_out,
        output [NBITS-1:0] y1_out
    );
    
    reg [NBITS-1:0] y0_out_reg = {NBITS{1'b0}};
    reg [NBITS-1:0] y1_out_reg = {NBITS{1'b0}};
    
    wire [47:0] dsp01_pcascade;
    wire [17:0] dsp01_bcascade;
    wire [17:0] dsp12_bcascade;
    wire [47:0] dsp23_pcascade;
    wire [17:0] dsp23_bcascade;
    
    wire [47:0] dsp1_out;
    wire [47:0] dsp3_out;    
    
    // Q17.13
    localparam A_FRAC_BITS = 13;
    // Q21.27
    localparam C_FRAC_BITS = 27;
    // 30 bits
    localparam A_BITS = 30;    
    
    wire [A_BITS-1:0] dsp0_Ain = dsp1_out[(C_FRAC_BITS-A_FRAC_BITS) +: A_BITS];
    wire [A_BITS-1:0] dsp1_Ain = dsp3_out[(C_FRAC_BITS-A_FRAC_BITS) +: A_BITS];
    wire [A_BITS-1:0] dsp2_Ain = dsp3_out[(C_FRAC_BITS-A_FRAC_BITS) +: A_BITS];
    wire [A_BITS-1:0] dsp3_Ain = dsp1_out[(C_FRAC_BITS-A_FRAC_BITS) +: A_BITS];

    `define COMMON_ATTRS `DE2_UNUSED_ATTRS,`CONSTANT_MODE_ATTRS,.BREG(2),.BCASCREG(1)
    // DSP0 has an MREG, but no PREG.
    // The head DSP needs a CC marker. Everyone else is in the proper domain.
    (* CUSTOM_CC_DST = CLKTYPE *)
    DSP48E2 #(`COMMON_ATTRS, .CREG(1),.MREG(1),.PREG(0),.AREG(0),.ACASCREG(0))
        u_dsp0(.CLK(clk),
               `D_UNUSED_PORTS,
               .B(coeff_dat_i),
               .BCOUT(dsp01_bcascade),
               .CEB1(coeff_wr_i),
               .CEB2(coeff_update_i),
               .CEM(1'b1),
               .CEC(1'b1),
               .C(y0_fir_in),
               .A(dsp0_Ain),
               .OPMODE({2'b00, `Z_OPMODE_C, `XY_OPMODE_M }),
               .ALUMODE(`ALUMODE_SUM_ZXYCIN),
               .CARRYINSEL(`CARRYINSEL_CARRYIN),
               .INMODE(0),
               .PCOUT(dsp01_pcascade));
    // DSP1 has a PREG.
    DSP48E2 #(`COMMON_ATTRS, `C_UNUSED_ATTRS, .B_INPUT("CASCADE"),.AREG(1),.PREG(1),.MREG(0))
        u_dsp1(.CLK(clk),
               .BCIN(dsp01_bcascade),
               .BCOUT(dsp12_bcascade),
               .CEB1(coeff_wr_i),
               .CEB2(coeff_update_i),
               .CEA2(1'b1),
               .CEP(1'b1),
               `C_UNUSED_PORTS,
               `D_UNUSED_PORTS,
	       .RSTP(rst),
               .PCIN(dsp01_pcascade),
               .P(dsp1_out),
               .A(dsp1_Ain),
               .OPMODE({2'b00, `Z_OPMODE_PCIN, `XY_OPMODE_M }),
               .ALUMODE(`ALUMODE_SUM_ZXYCIN),
               .CARRYINSEL(`CARRYINSEL_CARRYIN),
               .INMODE(0));
    // DSP2 has no PREG but an MREG.
     DSP48E2 #(`COMMON_ATTRS, .CREG(1),.MREG(1),.PREG(0),.AREG(0),.ACASCREG(0),.B_INPUT("CASCADE"))
        u_dsp2(.CLK(clk),
                .BCIN(dsp12_bcascade),
                .BCOUT(dsp23_bcascade),
                .CEB1(coeff_wr_i),
                .CEB2(coeff_update_i),
                .CEM(1'b1),
                `D_UNUSED_PORTS,
                .CEC(1'b1),
                .C(y1_fir_in),
                .A(dsp2_Ain),
                .OPMODE({2'b00, `Z_OPMODE_C, `XY_OPMODE_M }),
                .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                .CARRYINSEL(`CARRYINSEL_CARRYIN),
                .INMODE(0),
                .PCOUT(dsp23_pcascade));
    // and DSP3 has a PREG but no MREG                
    DSP48E2 #(`COMMON_ATTRS, `C_UNUSED_ATTRS,.MREG(0),.PREG(1),.AREG(1),.B_INPUT("CASCADE"))
        u_dsp3(.CLK(clk),
               .BCIN(dsp23_bcascade),
               .CEB1(coeff_wr_i),
               .CEB2(coeff_update_i),
               .CEA2(1'b1),
               .CEP(1'b1),
               `C_UNUSED_PORTS,
               `D_UNUSED_PORTS,
               .PCIN(dsp23_pcascade),
	       .RSTP(rst),
               .P(dsp3_out),
               .A(dsp3_Ain),
               .OPMODE({2'b00,`Z_OPMODE_PCIN, `XY_OPMODE_M }),
               .ALUMODE(`ALUMODE_SUM_ZXYCIN),
               .CARRYINSEL(`CARRYINSEL_CARRYIN),
               .INMODE(0));

    // Register the outputs. Adding one clock of output's not a big deal.
    always @(posedge clk) begin
        y0_out_reg <= dsp1_out[ C_FRAC_BITS - NFRAC +: NBITS ];
        y1_out_reg <= dsp3_out[ C_FRAC_BITS - NFRAC +: NBITS ];
    end
    assign y0_out = y0_out_reg;
    assign y1_out = y1_out_reg;

    `undef COMMON_ATTRS    
endmodule
