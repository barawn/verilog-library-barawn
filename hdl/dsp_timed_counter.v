`timescale 1ns / 1ps
`include "dsp_macros.vh"
// Programmable timed counter using a single DSP.
// Not exactly what sure to call this: it's a combination of a programmable interval counter and
// an up-counter in a single DSP.
//
// There are other ways to do this, but this uses literally nothing other than a
// single well-configured DSP.
//
// Note: this trick could also be done in quad SIMD mode to generate 3x 12-bit timers with a 12-bit
// interval as well, but because the widths are so different we leave that as a separate module.
//
// Parameters:
// MODE = "NORMAL" (default) - counter intervals run freely, count_out_valid is a flag (1-cycle high)
//                             and count_out is only valid for one cycle.
// MODE = "ACKNOWLEDGE"      - counter counts for one interval, and stops until a reset
//                             comes in, at which point it starts again. count_out_valid is *not*
//                             a flag - it goes high when the interval is reached and then
//                             clears after reset.
//                             NOTE: interval_load also acts as a reset.
module dsp_timed_counter( // main clock
                          input clk,
                          // Unused in normal mode. In acknowledge mode, clears the counter
                          // to start the next sequence (interval_load also resets).
                          input rst,
                          // count when this is 1
                          input count_in,
                          // interval to count over (number of clocks)
                          input [23:0] interval_in,
                          // load interval
                          input        interval_load,
                          // count output
                          output [24:0] count_out,
                          // count is valid
                          output        count_out_valid
    );
    
    parameter MODE = "NORMAL";
    
    // We use a single DSP in TWO24 mode.
    //
    // We use the pattern detect module with the mask set to cut off the top
    // ALU to act as a timer. We do NOT use the AUTORESET_PATDET because it
    // will reset the ENTIRE P-register, and we don't want that to happen
    // because we can't count in the next clock.
    //
    // There are minor stupid pet tricks that have to be done: if we set
    // an interval of, say, 50, we don't want to count from 0 to 50,
    // we want to count from 1 to 50, and we don't want to reset the P-register
    // because in that case we can't count when the P register is reset.
    //
    // So instead of resetting the P-register, we flop the OPMODE to
    // cut the P-register out of the equation. That is, when PATTERNDETECT
    // is set, OPMODE is 000_00_11 so that the ALU output becomes X only.
    // On other clocks, OPMODE is 010_00_11 (so OPMODE[5] is !PATTERNDETECT).
    //
    // The other trick we have to deal with is loading the pattern (in the
    // C register). When we load a new pattern, we need to reset the count
    // interval (otherwise it might miss the pattern if you change it to
    // something smaller). So when we do load a new pattern (a new interval)
    // we reset the P register. This introduces a dead clock where an input
    // can't be counted, but overall, that's fine.
    //
    // That's basically it. So we get:
    //
    // MODE="NORMAL" INTERVAL AND LOAD CASE:
    // 
    // clk  CEC C       CREG        XLOW    XHIGH   PLOW    PHIGH   PATTERNDETECT   OPMODE      interval#
    // 0    1   4       X           1       X       X       X       0               010_00_11   X
    // 1    0   X       4           1       1       0       0       0               010_00_11   1
    // 2    0   X       4           1       0       1       1       0               010_00_11   1
    // 3    0   X       4           1       1       2       1       0               010_00_11   1
    // 4    0   X       4           1       0       3       2       0               010_00_11   1
    // 5    0   X       4           1       1       4       2       1               000_00_11   2
    // Note here the output is valid (PATTERNDETECT=1) and the count is 2. Now the counter resets to 1 (b/c it's just X).
    // 6    0   X       4           1       1       1       1       0               010_00_11   2
    // 7    0   X       4           1       1       2       2       0               010_00_11   2
    // 8    0   X       4           1       1       3       3       0               010_00_11   2
    // 9    0   X       4           1       X       4       4       1               000_00_11   3
       
    // NOTE: Setting an interval of 0 actually results in an interval of 2^24. We allow this use case
    // by expanding the output by using the top CARRYOUT. This DOES NOT result in a "false valid" at CEC because
    // the PATTERNDETECT register is ALSO reset by RSTP.
    //
    // OPTIONAL ACKNOWLEDGE:
    // In some cases we may want to "hold" the output to be captured in a different domain.
    // In order to support this, "!PATTERNDETECT" is used to DISABLE CEP, and RSTP is
    // generated also by the incoming acknowledge. This results in:
    //
    // MODE="ACKNOWLEDGE" INTERVAL AND LOAD CASE:
    // 
    // clk  CEC C       CREG        XLOW    XHIGH   PLOW    PHIGH   PATTERNDETECT   ACK OPMODE      interval#
    // 0    1   4       X           1       X       X       X       0               0   010_00_11   X
    // 1    0   X       4           1       1       0       0       0               0   010_00_11   1
    // 2    0   X       4           1       0       1       1       0               0   010_00_11   1
    // 3    0   X       4           1       1       2       1       0               0   010_00_11   1
    // 4    0   X       4           1       0       3       2       0               0   010_00_11   1
    // 5    0   X       4           1       x       4       2       1               0   000_00_11   x
    // Note here the output is valid (PATTERNDETECT=1) so CEP is 0 and we do not change.
    // 6    0   X       4           1       x       4       2       1               0   010_00_11   x
    // 7    0   X       4           1       x       4       2       1               1   010_00_11   x
    // At this point ACK comes in and resets the P register, clearing PATTERNDETECT.
    // 8    0   X       4           1       1       0       0       0               0   010_00_11   2
    // 9    0   X       4           1       1       1       1       0               0   000_00_11   2
    // 10   0   X       4           1       1       2       2       0               0   000_00_11   2
    // 11   0   X       4           1       1       3       3       0               0   000_00_11   2
    // 12   0   X       4           1       x       4       4       1               0   000_00_11   x
    //
    // ACKNOWLEDGE mode obviously requires an extra LUT but it's not like this is a significant
    // cost compared to an entire extra set of registers needed for the clock crossing.
    // Also note that ACKNOWLEDGE mode has dead periods when the data is being transferred over,
    // and in addition obviously a timing exception needs to be made for that path since the data
    // is always static.
    wire [3:0]          dsp_CARRYOUT;
    wire [47:0]         dsp_AB = { {23{1'b0}}, count_in, 24'h1 };
    wire [47:0]         dsp_C = { {24{1'b0}}, interval_in };
    wire                dsp_CEC = interval_load;
    wire [47:0]         dsp_P;
    wire                dsp_PATTERNDETECT;
    localparam [47:0]   DSP_MASK = 48'hFFFFFF000000;
    wire [6:0]          dsp_OPMODE = { 1'b0, !dsp_PATTERNDETECT, 3'b000, 2'b11 };
    wire [3:0]          dsp_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    wire [2:0]          dsp_CARRYINSEL = `CARRYINSEL_CARRYIN;
    
    wire                dsp_RSTP;
    wire                dsp_CEP;
    generate
        if (MODE == "ACKNOWLEDGE") begin : ACK
            assign dsp_RSTP = dsp_CEC || rst;
            assign dsp_CEP = !dsp_PATTERNDETECT;
        end else begin : NRM // NORMAL mode
            assign dsp_RSTP = dsp_CEC;
            assign dsp_CEP = 1'b1;
        end 
    endgenerate
    // Note: we register both A and B to improve timing, because
    // the interval is free-running anyway. All this does is shift the input
    // relative to the interval by 1.
    DSP48E1 #(  .ALUMODEREG(0),
                .CARRYINSELREG(0),
                .OPMODEREG(0),
                .USE_SIMD("TWO24"),
                .AREG(1),
                .BREG(1),
                .CREG(1),
                .PREG(1),
                .USE_PATTERN_DETECT("PATDET"),
                .SEL_PATTERN("C"),
                .MASK( DSP_MASK ),
                .SEL_MASK("MASK"),
                .AUTORESET_PATDET("NO_RESET"),
                `D_UNUSED_ATTRS,
                `NO_MULT_ATTRS )
                u_dsp( .CLK(clk),
                       .A(`DSP_AB_A(dsp_AB)),
                       .B(`DSP_AB_B(dsp_AB)),
                       .C( dsp_C ),
                       `D_UNUSED_PORTS,
                       .CEA2(1'b1),
                       .CEB2(1'b1),
                       .CEP(dsp_CEP),
                       .CEC(dsp_CEC),
                       .CEM(1'b0),
                       .CECTRL(1'b0),
                       .CEINMODE(1'b0),
                       .CECARRYIN(1'b0),
                       .RSTA(1'b0),
                       .RSTB(1'b0),
                       .RSTC(1'b0),
                       .RSTP( dsp_RSTP ),
                       .RSTM(1'b0),
                       .RSTCTRL(1'b0),
                       .RSTINMODE(1'b0),
                       .ALUMODE( dsp_ALUMODE ),
                       .OPMODE( dsp_OPMODE ),
                       .CARRYOUT( dsp_CARRYOUT ),
                       .CARRYINSEL( dsp_CARRYINSEL ),
                       .CARRYIN( 1'b0 ),
                       .PATTERNDETECT( dsp_PATTERNDETECT ),
                       .P( dsp_P ) );

    assign count_out = { dsp_CARRYOUT[`DUAL_DSP_CARRY1], dsp_P[24 +: 24] };
    assign count_out_valid = dsp_PATTERNDETECT;
    
endmodule
