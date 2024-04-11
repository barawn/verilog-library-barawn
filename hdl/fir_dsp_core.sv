`timescale 1ns / 1ps
// basic parameterizable core DSP for FIR
// UPDATE: this core now handles loadable coefficients OPTIONALLY
// but only in a sequence load setup
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
// LOADABLE_B can either be HEAD, BODY, TAIL, or NONE (default)
// BODY/TAIL both use BCIN.
// Note that if you only have 1 just use HEAD.
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
        parameter PREG = 1,
	parameter LOADABLE_B = "NONE"
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
        output [29:0] acout_o,
        // use for loadable coefficient mode only
        input [17:0] bcin_i,
        output [17:0] bcout_o,
        input load_i,
        input update_i
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
    // the reason we need a billion damn options is b/c you CANNOT hook up a cascade input
    // if you don't plan on using it.
    generate
        if (ADD_PCIN == "TRUE") begin : CSC        
            if (USE_ACIN == "TRUE") begin : CSCIN
	       if (LOADABLE_B == "BODY" || LOADABLE_B == "TAIL") begin : ABPCSCIN
		// A, B, and P all have cascade inputs
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(2),
                           .BCASCREG(1),
			   .B_INPUT("CASCADE"),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
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
				    .BCIN( bcin_i ),
				    .CEB1( load_i ),
				    .CEB2( update_i ),
				    .BCOUT( bcout_o ),
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
               end else begin : APCSCIN // block: ABPCSCIN
		// A, P have cascade inputs
		DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
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
				    .CEB1( LOADABLE_B == "NONE" ? 1'b0 : load_i ),
				    .CEB2( LOADABLE_B == "NONE" ? 1'b0 : update_i ),
				    .BCOUT( bcout_o ),
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
		  end // block: APCSCIN	       
	    end // block: CSCIN
	    else begin : NCSCIN
	       if (LOADABLE_B == "BODY" || LOADABLE_B == "TAIL") begin : BPCSCIN
		// B, P have cascade inputs
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(2),
                           .BCASCREG(1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "CASCADE" ),
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
                                    .BCIN(bcin_i),
				    .CEB1( load_i ),
				    .CEB2( update_i ),
				    .BCOUT(bcout_o),
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
	       end else begin : PCSCIN // block: BPCSCIN
		// P has cascade input
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
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
				    .CEB1( LOADABLE_B == "NONE" ? 1'b0 : load_i ),
				    .CEB2( LOADABLE_B == "NONE" ? 1'b0 : update_i ),
				    .BCOUT(bcout_o),
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
	       end // block: PCSCIN	       
	    end // block: NCSCIN	   
        end // block: CSC
        else begin : NCSC
            if (USE_ACIN == "TRUE") begin : CSCIN
	        if (LOADABLE_B == "BODY" || LOADABLE_B == "TAIL") begin : ABCSCIN
		   // A, B have cascade inputs
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(2),
                           .BCASCREG(1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "CASCADE" ),
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
                                    .BCIN(bcin_i),
				    .CEB1( load_i ),
				    .CEB2( update_i ),
				    .BCOUT(bcout_o),
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
		end // block: ABCSCIN
	        else begin : ACSCIN
		   // A has cascade inputs
                   DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
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
				    .CEB1( LOADABLE_B == "NONE" ? 1'b0 : load_i ),
				    .CEB2( LOADABLE_B == "NONE" ? 1'b0 : update_i ),
				    .BCOUT( bcout_o ),
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
		end // block: ACSCIN
	    end // block: CSCIN
	    else begin : NCSCIN
	        if (LOADABLE_B == "BODY" || LOADABLE_B == "TAIL") begin : BCSCIN
		   // B only has cascaded inputs
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(2),
                           .BCASCREG(1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(CREG),
                           .DREG(DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "CASCADE" ),
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
                                    .BCIN(bcin_i),
				    .CEB1( load_i ),
				    .CEB2( update_i ),
				    .BCOUT(bcout_o),
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
		end // block: BCSCIN
	        else begin : NCSCIN
		   // No one has cascade inputs
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
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
				    .CEB1( LOADABLE_B == "NONE" ? 1'b0 : load_i ),
				    .CEB2( LOADABLE_B == "NONE" ? 1'b0 : update_i ),
				    .BCOUT(bcout_o),
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
		end // block: NCSCIN	       
            end // block: NCSCIN	   
        end // block: NCSC
       
    endgenerate                                
               
endmodule
