`timescale 1ns / 1ps
// basic parameterizable core DSP for FIR
// NOTE: this module DOES NOT handle programmable coefficients!
//
// parameters
// ADD_PCIN = "TRUE"/"FALSE" (default)
// USE_C = "TRUE" (default)/"FALSE"
// USE_ACIN = "TRUE"/"FALSE" (default)
// USE_ACOUT = "TRUE"/"FALSE" (default)
// SUBTRACT_A = "FALSE" (default) / "TRUE"
// AREG = 0 / 1 (default) / 2
// DREG = 0 / 1 (default)
// CREG = 0 / 1 (default)
// PREADD_REG = 0 (default) / 1 (adds register after preadder)
// MULT_REG = 0 (default) / 1 (adds register after multiplier)
//
// Note that a choice between PREADD_REG/MULT_REG for adding
// delay depends on different factors. If you have internal registers
// already (AREG/DREG are both not 0) then MREG is the preferential
// first choice.
//
// A/C/DREG all control input register delays.
//
// You should probably wrap these functions in something else
// to make sure that coefficients and data are passed properly.
//
module fir_dsp_core #(
        parameter ADD_PCIN = "FALSE",
        parameter USE_C = "TRUE",
        parameter USE_ACIN = "FALSE",
        parameter USE_ACOUT = "FALSE",
        parameter SUBTRACT_A = "FALSE",
        parameter SUBTRACT_C = "FALSE",
        parameter PREADD_REG = 0,
        parameter MULT_REG = 0,
        parameter ACASCREG = 1,
        parameter AREG = 1,
        parameter CREG = 1,
        parameter DREG = 1,
        parameter PREG = 1
    )(
        input clk_i,
        input [29:0] acin_i,
        input [47:0] pcin_i,
        input [25:0] a_i,
        input [25:0] d_i,
        input [17:0] b_i,
        input [47:0] c_i,
        output [47:0] p_o,
        output [47:0] pcout_o,
        output [29:0] acout_o
    );
    
    // INMODE is always either D+A2 or D-A2 
    // D+A2 = 00100
    // D-A2 = 01100
    localparam [4:0] INMODE = (SUBTRACT_A == "TRUE") ? 5'b01100 : 5'b00100;

    localparam [1:0] W_MUX = (USE_C == "TRUE") ? 2'b11 : 2'b00;
    localparam [2:0] Z_MUX = (ADD_PCIN == "TRUE") ? 3'b001 : 3'b000;
    localparam [8:0] OPMODE = { W_MUX, Z_MUX, 4'b0101 };
    localparam [3:0] ALUMODE = 4'b0000;
    
    localparam ADREG = PREADD_REG;
    localparam MREG = MULT_REG;
    
    // cascade input option
    localparam LOCAL_ACASCREG = (AREG == 0) ? 0 : 1;
    localparam MY_ACASCREG = (USE_ACOUT == "TRUE") ? ACASCREG : LOCAL_ACASCREG;
    // extend by 1, but top bits can stay zero
    wire [29:0] DSP_A = { {3{1'b0}}, a_i[25], a_i };
    wire [26:0] DSP_D = { d_i[25], d_i };
    wire [17:0] DSP_B = b_i;
    // if we're subtracting, we need to flip C
    wire [47:0] DSP_C = (SUBTRACT_C == "TRUE") ? ~c_i : c_i;        
    // and if we're subtracting C, we need to pass 1 to carryin to handle the two's complement
    wire CARRYIN = (SUBTRACT_C == "TRUE") ? 1 : 0;
    generate
        if (ADD_PCIN == "TRUE") begin : CSC        
            if (USE_ACIN == "TRUE") begin : CSCIN
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(1'b0),
                           .BCASCREG(1'b0),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL("AD"),
                           .BMULTSEL("B"),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .ACIN( acin_i ),
                                    .ACOUT( acout_o ),
                                    .CEA1( (AREG == 2) ? 1'b1 : 1'b0 ),
                                    .CEA2(1'b1),
                                    .CEAD( (PREADD_REG == 1) ? 1'b1 : 1'b0 ),
                                    .CEM( (MULT_REG == 1) ? 1'b1 : 1'b0 ),
                                    .B(DSP_B),
                                    .C(DSP_C),
                                    .CARRYIN(CARRYIN),
                                    .CEC(1'b1),
                                    .D(DSP_D),
                                    .CED(1'b1),
                                    .PCIN(pcin_i),
                                    .CLK(clk_i),
                                    .P(p_o),
                                    .CEP(1'b1),
                                    .PCOUT(pcout_o),
                                    .INMODE(INMODE),
                                    .OPMODE(OPMODE),
                                    .ALUMODE(ALUMODE));
                end else begin : NCSCIN
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(1'b0),
                           .BCASCREG(1'b0),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL("AD"),
                           .BMULTSEL("B"),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT( acout_o ),
                                    .CEA1( (AREG == 2) ? 1'b1 : 1'b0 ),
                                    .CEA2(1'b1),
                                    .CEAD( (PREADD_REG == 1) ? 1'b1 : 1'b0 ),
                                    .CEM( (MULT_REG == 1) ? 1'b1 : 1'b0 ),
                                    .B(DSP_B),
                                    .C(DSP_C),
                                    .CARRYIN(CARRYIN),
                                    .CEC(1'b1),
                                    .D(DSP_D),
                                    .CED(1'b1),
                                    .PCIN(pcin_i),
                                    .CLK(clk_i),
                                    .P(p_o),
                                    .CEP(1'b1),
                                    .PCOUT(pcout_o),
                                    .INMODE(INMODE),
                                    .OPMODE(OPMODE),
                                    .ALUMODE(ALUMODE));                
            end
            end else begin : NCSC
            if (USE_ACIN == "TRUE") begin : CSCIN
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(1'b0),
                           .BCASCREG(1'b0),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL("AD"),
                           .BMULTSEL("B"),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .ACIN( acin_i ),
                                    .ACOUT(acout_o),                           
                                    .CEA1( (AREG == 2) ? 1'b1 : 1'b0 ),
                                    .CEA2(1'b1),
                                    .CEAD( (PREADD_REG == 1) ? 1'b1 : 1'b0 ),
                                    .CEM( (MULT_REG == 1) ? 1'b1 : 1'b0 ),                                
                                    .B(DSP_B),
                                    .C(DSP_C),
                                    .CARRYIN(CARRYIN),
                                    .CEC(1'b1),
                                    .D(DSP_D),
                                    .CED(1'b1),
                                    .CLK(clk_i),
                                    .P(p_o),
                                    .CEP(1'b1),
                                    .PCOUT(pcout_o),
                                    .INMODE(INMODE),
                                    .OPMODE(OPMODE),
                                    .ALUMODE(ALUMODE));
            end else begin : NCSCIN
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(1'b0),
                           .BCASCREG(1'b0),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL("AD"),
                           .BMULTSEL("B"),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT(acout_o),
                                    .CEA1( (AREG == 2) ? 1'b1 : 1'b0 ),
                                    .CEA2(1'b1),
                                    .CEAD( (PREADD_REG == 1) ? 1'b1 : 1'b0 ),
                                    .CEM( (MULT_REG == 1) ? 1'b1 : 1'b0 ),                                
                                    .B(DSP_B),
                                    .C(DSP_C),
                                    .CARRYIN(CARRYIN),
                                    .CEC(1'b1),
                                    .D(DSP_D),
                                    .CED(1'b1),
                                    .CLK(clk_i),
                                    .P(p_o),
                                    .CEP(1'b1),
                                    .PCOUT(pcout_o),
                                    .INMODE(INMODE),
                                    .OPMODE(OPMODE),
                                    .ALUMODE(ALUMODE));
            end
        end
    endgenerate                                
               
endmodule
