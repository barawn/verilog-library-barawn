`timescale 1ns / 1ps
`include "dsp_macros.vh"
// so sick of trying to remember how to do this, sigh
module four12_dsp #(
        parameter USE_CE = 0,
        parameter USE_RST = 0,
        parameter ABREG = 1,
        parameter CREG = 1,
        parameter PREG = 1,
        parameter CASCADE = "FALSE",
        parameter [47:0] RND = {48{1'b0}},
        parameter [3:0] ALUMODE = `ALUMODE_SUM_ZXYCIN,
        parameter [8:0] OPMODE = { 2'b00, `Z_OPMODE_C, `Y_OPMODE_0, `X_OPMODE_AB }
    )(
        input clk_i,
        input ce_ab_i,
        input rst_ab_i,
        input ce_c_i,
        input rst_c_i,
        input ce_p_i,
        input rst_p_i,
        input [12*4-1:0] AB_i,
        input [12*4-1:0] C_i,
        output [12*4-1:0] P_o,
        output [3:0] CARRY_o,
        input [47:0] pc_i,
        output [47:0] pc_o
    );
    
    wire [47:0] dsp_AB = AB_i;
    wire [47:0] dsp_C = C_i;
    wire [47:0] dsp_P;
    assign P_o = dsp_P;
    
    // i should make this definable or something, sigh
    generate
        if (CASCADE == "FALSE") begin : NCSC
            DSP48E2 #(`NO_MULT_ATTRS,
                      `CONSTANT_MODE_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("FOUR12"),
                      .RND(RND),
                      .AREG(ABREG),
                      .BREG(ABREG),
                      .CREG(CREG),
                      .PREG(PREG))
                      u_dsp(.CLK(clk_i),
                            .A(`DSP_AB_A(dsp_AB)),
                            .B(`DSP_AB_B(dsp_AB)),
                            .C(dsp_C),
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .CARRYIN(1'b0),
                            .CEA2(USE_CE == 1 ? ce_ab_i : 1'b1 ),
                            .CEA1(ABREG == 1 ? (USE_CE == 1 ? ce_ab_i : 1'b1) : 1'b0 ),
                            .CEB2(USE_CE == 1 ? ce_ab_i : 1'b1 ),
                            .CEB1(ABREG == 1 ? (USE_CE == 1 ? ce_ab_i : 1'b1) : 1'b0 ),
                            .CEC(USE_CE == 1 ? ce_c_i : 1'b1),
                            .CEP(USE_CE == 1 ? ce_p_i : 1'b1),
                            .RSTA(USE_RST == 1 ? rst_ab_i : 1'b0),
                            .RSTB(USE_RST == 1 ? rst_ab_i : 1'b0),
                            .RSTC(USE_RST == 1 ? rst_c_i : 1'b0),
                            .RSTP(USE_RST == 1 ? rst_p_i : 1'b0),
                            .ALUMODE(ALUMODE),
                            .OPMODE(OPMODE),
                            .PCOUT(pc_o),
                            .P(P_o),
                            .CARRYOUT(CARRY_o));
        end else begin : CSC
            DSP48E2 #(`NO_MULT_ATTRS,
                      `CONSTANT_MODE_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("FOUR12"),
                      .RND(RND),                      
                      .AREG(ABREG),
                      .BREG(ABREG),
                      .CREG(CREG),
                      .PREG(PREG))
                      u_dsp(.CLK(clk_i),
                            .A(`DSP_AB_A(dsp_AB)),
                            .B(`DSP_AB_B(dsp_AB)),
                            .C(dsp_C),
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .CARRYIN(1'b0),
                            .CEA2(USE_CE == 1 ? ce_ab_i : 1'b1 ),
                            .CEA1(ABREG == 1 ? (USE_CE == 1 ? ce_ab_i : 1'b1) : 1'b0 ),
                            .CEB2(USE_CE == 1 ? ce_ab_i : 1'b1 ),
                            .CEB1(ABREG == 1 ? (USE_CE == 1 ? ce_ab_i : 1'b1) : 1'b0 ),
                            .CEC(USE_CE == 1 ? ce_c_i : 1'b1),
                            .CEP(USE_CE == 1 ? ce_p_i : 1'b1),
                            .RSTA(USE_RST == 1 ? rst_ab_i : 1'b0),
                            .RSTB(USE_RST == 1 ? rst_ab_i : 1'b0),
                            .RSTC(USE_RST == 1 ? rst_c_i : 1'b0),
                            .RSTP(USE_RST == 1 ? rst_p_i : 1'b0),
                            .ALUMODE(ALUMODE),
                            .OPMODE(OPMODE),
                            .PCIN(pc_i),
                            .PCOUT(pc_o),
                            .P(P_o),
                            .CARRYOUT(CARRY_o));
        end
    endgenerate
            
endmodule
