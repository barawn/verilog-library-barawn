`timescale 1ns / 1ps

// notes: set unused A/B/C/D ports to 1, select input register, 0 clock enable and 0 reset

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

`define CONSTANT_MODE_ATTRS .ALUMODEREG(0),.INMODEREG(0),.OPMODEREG(0),.CARRYINSELREG(0)
`define NO_MULT_ATTRS .USE_MULT("NONE"),.MREG(0)

// DSP-based 48-bit counter with variable terminal count. This uses the pattern detector
// for its implementation. Kindof ridiculous that this doesn't exist already.
// This can be made into a fixed terminal count with a parameter. In that case tcount_i
// and update_tcount_i are ignored.
// If the parameter RESET_TCOUNT_AT_RESET is TRUE, the terminal count is reset at
// rst_i as well, and must be updated.
module dsp_counter_terminal_count(
        input           clk_i,
        input           rst_i,
        input           count_i,
        input [47:0]    tcount_i,
        input           update_tcount_i,
        output          tcount_reached_o
    );
    
    parameter FIXED_TCOUNT = "FALSE";
    parameter FIXED_TCOUNT_VALUE = 0;
    parameter RESET_TCOUNT_AT_RESET = "TRUE";
   
    // for simulation
    wire [47:0] current_count;

    reg rst_or_update = 0;
    always @(posedge clk_i) begin
        if (update_tcount_i) rst_or_update <= 1;
        else rst_or_update <= rst_i;
    end
    
    // ALUMODE results in Z+X+Y+CIN. Z = P, X=0, Y=0.
    localparam [3:0] ALUMODE = `ALUMODE_SUM_ZXYCIN;
    // Z = P, X=0, Y=0.
    localparam [6:0] OPMODE = { `Z_OPMODE_P, `Y_OPMODE_0 , `X_OPMODE_0 };
    // doesn't matter
    localparam [3:0] INMODE = 4'b0000;
    
    generate
        if (FIXED_TCOUNT == "TRUE") begin : FIXED
            DSP48E1 #( `A_UNUSED_ATTRS, `B_UNUSED_ATTRS, `D_UNUSED_ATTRS, `CONSTANT_MODE_ATTRS, `NO_MULT_ATTRS,
                           .PREG(1'b1),.CREG(1'b1),.CARRYINREG(1'b0),
                           .AUTORESET_PATDET("RESET_MATCH"),.MASK({48{1'b0}}),.SEL_PATTERN("PATTERN"),.PATTERN(FIXED_TCOUNT_VALUE),.USE_PATTERN_DETECT("PATDET")
                         )
                    u_counter( `A_UNUSED_PORTS, `B_UNUSED_PORTS, `C_UNUSED_PORTS, `D_UNUSED_PORTS,
                               .CEP(count_i),.RSTP(rst_i),
                               .CARRYIN(1'b1),.CARRYINSEL(`CARRYINSEL_CARRYIN),
                               .OPMODE(OPMODE),.ALUMODE(ALUMODE),.INMODE(INMODE),
                               .CLK(clk_i),
                               .PATTERNDETECT(tcount_reached_o),.P(current_count));    
        end else begin : VAR        
            DSP48E1 #( `A_UNUSED_ATTRS, `B_UNUSED_ATTRS, `D_UNUSED_ATTRS, `CONSTANT_MODE_ATTRS, `NO_MULT_ATTRS,
                       .PREG(1'b1),.CREG(1'b1),.CARRYINREG(1'b0),
                       .AUTORESET_PATDET("RESET_MATCH"),.MASK({48{1'b0}}),.SEL_PATTERN("C"),.USE_PATTERN_DETECT("PATDET")
                     )
                u_counter( `A_UNUSED_PORTS, `B_UNUSED_PORTS, `D_UNUSED_PORTS,
                           .C(tcount_i),.RSTC(RESET_TCOUNT_AT_RESET == "TRUE" ? rst_i : 1'b0),.CEC(update_tcount_i),
                           .CEP(count_i),.RSTP(rst_or_update),
                           .CARRYIN(1'b1),.CARRYINSEL(`CARRYINSEL_CARRYIN),
                           .OPMODE(OPMODE),.ALUMODE(ALUMODE),.INMODE(INMODE),
                           .CLK(clk_i),
                           .PATTERNDETECT(tcount_reached_o),.P(current_count));    
       end
   endgenerate
    
endmodule
