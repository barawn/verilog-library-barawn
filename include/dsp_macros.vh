// notes: set unused A/B/C/D ports to 1, select input register, 0 clock enable and 0 reset

// for a dsp48e2
`define W_OPMODE_0              2'b00
`define W_OPMODE_P              2'b01
`define W_OPMODE_RND            2'b10
`define W_OPMODE_C              2'b11

`define X_OPMODE_0              2'b00
// the 01 case is XY_OPMODE_M
`define X_OPMODE_P              2'b10
`define X_OPMODE_AB             2'b11

`define Y_OPMODE_0              2'b00
// the 01 case is XY_OPMODE_M
`define Y_OPMODE_MINUS1         2'b10
`define Y_OPMODE_C              2'b11

`define Z_OPMODE_0              3'b000
`define Z_OPMODE_PCIN           3'b001
`define Z_OPMODE_P              3'b010
`define Z_OPMODE_C              3'b011
// the 100 case is OPMODE_MACC_EXTEND
`define Z_OPMODE_PCIN_SHIFT17   3'b101
`define Z_OPMODE_P_SHIFT17      3'b110
// combo opmodes
`define XY_OPMODE_M             4'b0101
`define OPMODE_MACC_EXTEND      7'b1001000

// INMODE handles all the multiplier stuff, which honestly
// I've never used yet. So just save those for later.

`define ALUMODE_SUM_ZXYCIN              4'b0000
`define ALUMODE_Z_MINUS_XYCIN           4'b0011
`define ALUMODE_XYCIN_MINUS_Z_MINUS_1   4'b0001
`define ALUMODE_MINUS_ZXYCIN            4'b0010

`define CARRYINSEL_CARRYIN              3'b000
`define CARRYINSEL_PCIN_ROUND_INF       3'b001
`define CARRYINSEL_CARRYCASCIN          3'b010
`define CARRYINSEL_PCIN_ROUND_ZERO      3'b011
`define CARRYINSEL_CARRYCASCOUT         3'b100
`define CARRYINSEL_P_ROUND_INF          3'b101
`define CARRYINSEL_ROUND_AXB            3'b110
`define CARRYINSEL_P_ROUND_ZERO         3'b111

`define A_UNUSED_PORTS .A({30{1'b1}}),.CEA1(1'b0),.CEA2(1'b0),.RSTA(1'b0)
`define A_UNUSED_ATTRS .ACASCREG(1'b1),.AREG(1'b1)
`define B_UNUSED_PORTS .B({18{1'b1}}),.CEB1(1'b0),.CEB2(1'b0),.RSTB(1'b0)
`define B_UNUSED_ATTRS .BCASCREG(1'b1),.BREG(1'b1)
`define C_UNUSED_PORTS .C({48{1'b1}}),.CEC(1'b0),.RSTC(1'b0)
`define C_UNUSED_ATTRS .CREG(1'b1)
`define D_UNUSED_PORTS .D({25{1'b1}}),.CED(1'b0),.RSTD(1'b0)
`define D_UNUSED_ATTRS .DREG(1'b1),.USE_DPORT("FALSE")
`define DE2_UNUSED_ATTRS .DREG(1'b1),.AMULTSEL("A")

`define CONSTANT_MODE_ATTRS .ALUMODEREG(0),.INMODEREG(0),.OPMODEREG(0),.CARRYINSELREG(0)
`define NO_MULT_ATTRS .USE_MULT("NONE"),.MREG(0)

// In normal DSP mode the carry bit is 3
`define DSP_CARRY 3

// In SIMD24 mode the two carry bits are 1 and 3.
`define DUAL_DSP_CARRY0 1
`define DUAL_DSP_CARRY1 3

// In FOUR12 mode the carry bits are 0/1/2/3
`define QUAD_DSP_CARRY0 0
`define QUAD_DSP_CARRY1 1
`define QUAD_DSP_CARRY2 2
`define QUAD_DSP_CARRY3 3

// This is a helper function to pick off the A/B inputs when used as a 48-bit input
`define DSP_AB_A( val ) val[ 18 +: 30 ]
`define DSP_AB_B( val ) val[ 0 +: 18 ]
