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
//
// CLKTYPE allows cross-clock for coeff_dat using CUSTOM_CC_DST
module fir_dsp_core #(
        parameter ADD_PCIN = "FALSE",
        parameter USE_C = "TRUE",
        parameter USE_ACIN = "FALSE",
        parameter USE_ACOUT = "FALSE",
        parameter SUBTRACT_A = "FALSE",
        parameter SUBTRACT_C = "FALSE",
	parameter USE_D = "TRUE",
        parameter PREADD_REG = 0,
        parameter MULT_REG = 0,
        parameter ACASCREG = 1,
        parameter AREG = 1,
        parameter CREG = 1,
        parameter DREG = 1,
        parameter PREG = 1,
	parameter LOADABLE_B = "NONE",
	parameter CLKTYPE = "NONE"
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
    
    // INMODE is always either D+A2 or D-A2, or just +/-A2.
    // A2 gets selected when AMULTSEL is just A instead of AD
    // D+A2 = 00100
    // D-A2 = 01100
    // A2   = 00000
    // -A2  = 01000
    localparam [4:0] INMODE = { 1'b0,
				(SUBTRACT_A == "TRUE") ? 1'b1 : 1'b0,
				(USE_D == "TRUE") ? 1'b1 : 1'b0,
				2'b00 };

    localparam [1:0] W_MUX = (USE_C == "TRUE") ? 2'b11 : 2'b00;
    localparam [2:0] Z_MUX = (ADD_PCIN == "TRUE") ? 3'b001 : 3'b000;
    localparam [8:0] OPMODE = { W_MUX, Z_MUX, 4'b0101 };
    localparam [3:0] ALUMODE = 4'b0000;
    
    localparam ADREG = PREADD_REG;
    localparam MREG = MULT_REG;

    // cascade input option
    localparam LOCAL_ACASCREG = (AREG == 0) ? 0 : 1;
    localparam MY_ACASCREG = (USE_ACOUT == "TRUE") ? ACASCREG : LOCAL_ACASCREG;
   
    // Dport usage, for low power
    localparam  AMULTSEL = (USE_D == "TRUE") ? "AD" : "A";
    localparam  MY_DREG = (USE_D == "TRUE") ? DREG : 1'b1;
    wire	       CED = (USE_D == "TRUE") ? 1'b1 : 1'b0;

    // Cport usage, for low power
    localparam  MY_CREG = (USE_C == "TRUE") ? CREG : 1'b1;
    wire		CEC = (USE_C == "TRUE") ? 1'b1 : 1'b0;
   

   
    // extend by 4 or 1. Extend by 4 b/c if we don't use Dport, gets passed to multiplier
    wire [29:0] DSP_A = { {4{a_i[25]}}, a_i };
    // if we don't use Dport tie everything high for lowest leakage
    wire [26:0]	DSP_D = (USE_D == "TRUE") ? { d_i[25], d_i } : {27{1'b1}};   
    wire [17:0] DSP_B = b_i;
    // if we're subtracting, we need to flip C
    wire [47:0] DSP_C = (USE_C == "TRUE") ? ((SUBTRACT_C == "TRUE") ? ~c_i : c_i) : {48{1'b1}} ;        
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
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
		(* CUSTOM_CC_DST = CLKTYPE *)
		DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "CASCADE" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
		(* CUSTOM_CC_DST = CLKTYPE *)		
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "CASCADE" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
		   (* CUSTOM_CC_DST = CLKTYPE *)
                   DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "CASCADE" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
		(* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(AREG),
                           .BREG(LOADABLE_B == "NONE" ? 0 : 2),
                           .BCASCREG(LOADABLE_B == "NONE" ? 0 : 1),
                           .CARRYINREG(1'b0),
                           .CARRYINSELREG(1'b0),
                           .CREG(MY_CREG),
                           .DREG(MY_DREG),
                           .INMODEREG(1'b0),
                           .MREG(MREG),
                           .OPMODEREG(1'b0),
                           .PREG(PREG),
                           .B_INPUT( "DIRECT" ),
                           .PREADDINSEL("A"),
                           .AMULTSEL(AMULTSEL),
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
                                    .CEC(CEC),
                                    .D(DSP_D),
                                    .CED(CED),
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
