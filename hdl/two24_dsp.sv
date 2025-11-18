`timescale 1ns / 1ps
`include "dsp_macros.vh"
// so sick of trying to remember how to do this, sigh
module two24_dsp #(
        parameter USE_CE = 0,
        parameter USE_RST = 0,
        parameter USE_AB = 1,
        parameter USE_C = 1,
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
        input [24*2-1:0] AB_i,
        input [24*2-1:0] C_i,
        output [24*2-1:0] P_o,
        output [1:0] CARRY_o,
        input [47:0] pc_i,
        output [47:0] pc_o
    );
        
    // If AB or C is unused, the proper lowest power
    // method is tie everything high, register enabled,
    // CE disabled, and reset low.    
    wire [47:0] dsp_AB = (USE_AB != 0) ? AB_i : {48{1'b1}};
    wire [47:0] dsp_C = (USE_C != 0) ? C_i : {48{1'b1}};
    wire [47:0] dsp_P;
    wire [3:0] dsp_carry;
    assign CARRY_o[0] = dsp_carry[`DUAL_DSP_CARRY0];
    assign CARRY_o[1] = dsp_carry[`DUAL_DSP_CARRY1];
    assign P_o = dsp_P;
    
    localparam DSP_AREG = (USE_AB != 0) ? ABREG : 1'b1;
    localparam DSP_ACASCREG = DSP_AREG;
    localparam DSP_BREG = (USE_AB != 0) ? ABREG : 1'b1;
    localparam DSP_BCASCREG = DSP_BREG;
    localparam DSP_CREG = (USE_C != 0) ? CREG : 1'b1;
    
    wire CEA2 = (USE_AB != 0) ? (USE_CE == 1 ? ce_ab_i : 1'b1 ) : 1'b0;
    wire CEB2 = CEA2;
    // only use when ABREG=2, otherwise tie low
    wire CEA1 = (USE_AB != 0) ? (ABREG == 2 ? (USE_CE == 1 ? ce_ab_i : 1'b1) : 1'b0) : 1'b0;
    wire CEB1 = CEA1;
    wire RSTA = (USE_AB != 0 && USE_RST == 1) ? rst_ab_i : 1'b0;
    wire RSTB = RSTA;
    
    wire CEC = (USE_C != 0) ? (USE_CE == 1 ? ce_c_i : 1'b1) : 1'b0;
    wire RSTC = (USE_C != 0 && USE_RST == 1) ? rst_c_i : 1'b0;    

    wire CEP = (PREG == 1) ? (USE_CE == 1 ? ce_p_i : 1'b1) : 1'b0;
    
    // i should make this definable or something, sigh
    generate
        if (CASCADE == "FALSE") begin : NCSC
            DSP48E2 #(`NO_MULT_ATTRS,
                      `CONSTANT_MODE_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("TWO24"),
                      .RND(RND),
                      .AREG(DSP_AREG),
                      .ACASCREG(DSP_ACASCREG),
                      .BREG(DSP_BREG),
                      .BCASCREG(DSP_BCASCREG),
                      .CREG(DSP_CREG),
                      .PREG(PREG))
                      u_dsp(.CLK(clk_i),
                            .A(`DSP_AB_A(dsp_AB)),
                            .B(`DSP_AB_B(dsp_AB)),
                            .C(dsp_C),
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .CARRYIN(1'b0),
                            .CEA2(CEA2),
                            .CEA1(CEA1),
                            .CEB2(CEB2),
                            .CEB1(CEB1),
                            .CEC(CEC),
                            .CEP(CEP),
                            .RSTA(RSTA),
                            .RSTB(RSTB),
                            .RSTC(RSTC),
                            .RSTP(USE_RST == 1 ? rst_p_i : 1'b0),
                            .ALUMODE(ALUMODE),
                            .OPMODE(OPMODE),
                            .PCOUT(pc_o),
                            .P(P_o),
                            .CARRYOUT(dsp_carry));
        end else begin : CSC
            DSP48E2 #(`NO_MULT_ATTRS,
                      `CONSTANT_MODE_ATTRS,
                      `DE2_UNUSED_ATTRS,
                      .USE_SIMD("TWO24"),
                      .RND(RND),
                      .AREG(DSP_AREG),
                      .ACASCREG(DSP_ACASCREG),
                      .BREG(DSP_BREG),
                      .BCASCREG(DSP_BCASCREG),
                      .CREG(DSP_CREG),
                      .PREG(PREG))
                      u_dsp(.CLK(clk_i),
                            .A(`DSP_AB_A(dsp_AB)),
                            .B(`DSP_AB_B(dsp_AB)),
                            .C(dsp_C),
                            `D_UNUSED_PORTS,
                            .CARRYINSEL(`CARRYINSEL_CARRYIN),
                            .CARRYIN(1'b0),
                            .CEA2(CEA2),
                            .CEA1(CEA1),
                            .CEB2(CEB2),
                            .CEB1(CEB1),
                            .CEC(CEC),
                            .CEP(CEP),
                            .RSTA(RSTA),
                            .RSTB(RSTB),
                            .RSTC(RSTC),
                            .RSTP(USE_RST == 1 ? rst_p_i : 1'b0),
                            .ALUMODE(ALUMODE),
                            .OPMODE(OPMODE),
                            .PCIN(pc_i),
                            .PCOUT(pc_o),
                            .P(P_o),
                            .CARRYOUT(dsp_carry));
        end
    endgenerate
            
endmodule
