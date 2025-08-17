`timescale 1ns / 1ps
// basic parameterizable core DSP for FIR
// UPDATE: this core now handles loadable coefficients OPTIONALLY
// but only in a sequence load setup
//
// parameters
// ADD_PCIN = "TRUE"/"FALSE" (default)
// USE_C = "TRUE" (default)/"FALSE"
// USE_RND = "TRUE"/"FALSE" (default) -- READ NOTE BELOW
// RND_VAL = {48{1'b0}} (default)     -- READ NOTE BELOW
// USE_PATTERN = "TRUE"/"FALSE" (default) - use pattern detect
// PATTERN = {48{1'b0}} (default) -- pattern to look for
// USE_ACIN = "TRUE"/"FALSE" (default)
// USE_ACOUT = "TRUE"/"FALSE" (default)
// SUBTRACT_A = "FALSE" (default) / "TRUE"
// AREG = 0 / 1 (default) / 2
// DREG = 0 / 1 (default)
// CREG = 0 / 1 (default)
// PREADD_REG = 0 (default) / 1 (adds register after preadder)
// MULT_REG = 0 (default) / 1 (adds register after multiplier)
//
////////////////////////////////////////////
//
// USE_RND NOTES:
// DSP48s fundamentally have a 4-element ALU, however, the
// multiplier takes 2 slots for its partial products. So we only
// have 2 available slots, the W and Z inputs.
//
// fir_dsp_core allows for using any 2 of C, PCIN, or RND for
// those slots, but you cannot use all 3. Thankfully Vivado
// now enables $fatal on invalid parameters, so elaboration
// will fail if ADD_PCIN = "TRUE", USE_C = "TRUE" and
// USE_RND = "TRUE".
//
// You can use USE_RND to add a constant rather than feeding
// a constant value into the C port. Dunno if this is better
// or if they're functionally identical.
//
////////////////////////////////////////////
//
// INPUT REGISTER NOTES:
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
////////////////////////////////////////////
// LOADABLE_B NOTES:
// LOADABLE_B can either be HEAD, BODY, TAIL, or NONE (default)
// BODY/TAIL both use BCIN.
// Note that if you only have 1 just use HEAD.
//
///////////////////////////////////////////
// CLKTYPE allows cross-clock for coeff_dat using CUSTOM_CC_DST
///////////////////////////////////////////
module fir_dsp_core #(
        parameter ADD_PCIN = "FALSE",
        parameter USE_C = "TRUE",
	parameter USE_RND = "FALSE",
	parameter RND_VAL = {48{1'b0}},
	parameter USE_PATTERN = "FALSE",
	parameter PATTERN_VAL = {48{1'b0}},
	parameter MASK_VAL = {48{1'b1}},
    parameter USE_CE = "FALSE",
	parameter USE_CARRYIN = "FALSE",
        parameter USE_ACIN = "FALSE",
        parameter USE_ACOUT = "FALSE",
        parameter SUBTRACT_A = "FALSE",
        parameter SUBTRACT_C = "FALSE",
	parameter USE_D = "TRUE",
        parameter PREADD_REG = 0,
        parameter MULT_REG = 0,
        // NOTE NOTE NOTE: This is the number of registers
        // IN THE CASCADE path
        parameter ACASCREG = 1,
        // NOTE NOTE NOTE: This is NOT the DSP's "AREG"!
        //  - it is the number of registers IN THE
        // PREADD/MULT/ALU path!
        parameter AREG = 1,
        parameter CREG = 1,
        parameter DREG = 1,
        parameter PREG = 1,
	parameter LOADABLE_B = "NONE",
	parameter CLKTYPE = "NONE"
    )(
        input clk_i,
        input ce_i,
        input rst_i,
        input [29:0] acin_i,
        input [47:0] pcin_i,
        input [25:0] a_i,
        input [25:0] d_i,
        input [17:0] b_i,
        input [47:0] c_i,
        input carryin_i,
        output [47:0] p_o,
        output pattern_o,
        output [47:0] pcout_o,
        output [29:0] acout_o,
        // use for loadable coefficient mode only
        input [17:0] bcin_i,
        output [17:0] bcout_o,
        input load_i,
        input update_i
    );

    wire ce = (USE_CE == "TRUE") ? ce_i : 1'b1;
    
    `define RESETS( port )  \
        .RSTA( port ),      \
        .RSTB( port ),      \
        .RSTC( port ),      \
        .RSTD( port ),      \
        .RSTP( port )

    // pattern detection
    localparam USE_PATTERN_DETECT = USE_PATTERN == "TRUE" ? "PATDET" : "NO_PATDET";
    localparam SEL_PATTERN = "PATTERN";
    localparam [47:0] PATTERN = PATTERN_VAL;
    localparam [47:0] MASK = MASK_VAL;
    
    // figure out the ACTUAL DSP AREG
    localparam MAX_AREG = (ACASCREG > AREG) ? ACASCREG : AREG;
    localparam DSP_AREG = (USE_ACOUT != "FALSE") ? MAX_AREG : AREG;
        
    // this is set if we need to jump back a register in
    // the path
    // Note that if the user screws up and specifies ACASCREG = 2
    // even though they're not using it, we need to ignore them.
    localparam USE_A1_INMODE = (ACASCREG == 2 && AREG == 1 && USE_ACOUT == "TRUE") ? 1'b1 : 1'b0;
    localparam USE_D_INMODE = (USE_D == "TRUE") ? 1'b1 : 1'b0;
    localparam SUBTRACT_A_INMODE = (SUBTRACT_A == "TRUE") ? 1'b1 : 1'b0;
    // INMODE is always either D+A or D-A, or just +/-A.
    // We use A2 unless USE_A1 is set, which is the same thing
    // as INMODE[0].
    
    // INMODE is always either D+A2 or D-A2, or just +/-A2.
    // A2 gets selected when AMULTSEL is just A instead of AD
    // D+A2 = 00100
    // D+A1 = 00101
    // D-A2 = 01100
    // D-A1 = 01101
    // A2   = 00000
    // A1   = 00001
    // -A2  = 01000
    // -A1  = 01001
    localparam [4:0] DSP_INMODE = 
            { 1'b0,
              SUBTRACT_A_INMODE,
              USE_D_INMODE,
              1'b0,
              USE_A1_INMODE };

    // FIGURING OUT THE W AND Z MUX:
    // First, check the parameters using a generate block.
    generate
       if (USE_C == "TRUE" && USE_RND == "TRUE" && ADD_PCIN == "TRUE") begin : INVALID
	  $fatal(1, "Only 2 of USE_C/USE_RND/ADD_PCIN can be TRUE - aborting");
       end
       if (SUBTRACT_C == "TRUE" && USE_CARRYIN == "TRUE") begin : INVALID2
      $fatal(1, "USE_CARRYIN and SUBTRACT_C cannot both be TRUE - aborting");
      end       
    endgenerate
   
    // W mux determination: (00, 10, or 11 only)
    localparam W_ANY = ((USE_C == "TRUE") || (USE_RND == "TRUE")) ? 1'b1 : 1'b0;
    localparam W_IS_C = ((USE_C == "TRUE") && (USE_RND == "FALSE")) ? 1'b1 : 1'b0;
    localparam [1:0] W_MUX = { W_ANY, W_IS_C };
    // Z mux determination: (000, 001, 011 only)
    // C uses W preferentially but uses Z if RND is used and it's available
    localparam Z_IS_C = ((USE_C == "TRUE") && (USE_RND == "TRUE")) ? 1'b1 : 1'b0;
    localparam Z_ANY = (Z_IS_C == 1'b1) || (ADD_PCIN == "TRUE") ? 1'b1 : 1'b0;
    localparam [2:0] Z_MUX = { 1'b0, Z_IS_C, Z_ANY };   
      
    localparam [8:0] OPMODE = { W_MUX, Z_MUX, 4'b0101 };
    localparam [3:0] ALUMODE = 4'b0000;

    // ?!?!? is this correct? I don't think so???
    localparam ADREG = (USE_D == "TRUE") ? PREADD_REG : 1'b1;
    localparam MREG = MULT_REG;

    // cascade input option
    localparam LOCAL_ACASCREG = (AREG == 0) ? 0 : 1;
    localparam MY_ACASCREG = (USE_ACOUT == "TRUE") ? ACASCREG : LOCAL_ACASCREG;
   
    // Dport usage, for low power
    localparam  AMULTSEL = (USE_D == "TRUE") ? "AD" : "A";
    localparam  MY_DREG = (USE_D == "TRUE") ? DREG : 1'b1;
    wire	       CED = (USE_D == "TRUE") ? ce : 1'b0;

    // Cport usage, for low power
    localparam  MY_CREG = (USE_C == "TRUE") ? CREG : 1'b1;
    wire		CEC = (USE_C == "TRUE") ? ce : 1'b0;
   
    // parameterize the clock enables
    `define CLOCK_ENABLES( port )   \
        .CEA1(DSP_AREG == 2 ? port : 1'b0),                 \
        .CEA2(AREG != 0 ? port : 1'b0),                 \
        .CEM(MULT_REG != 0 ? port : 1'b0),                 \
        .CEP(PREG != 0 ? port : 1'b0),                \
        .CEAD(PREADD_REG != 0 ? port : 1'b0)
   
    // extend by 4 or 1. Extend by 4 b/c if we don't use Dport, gets passed to multiplier
    wire [29:0] DSP_A = { {4{a_i[25]}}, a_i };
    // if we don't use Dport tie everything high for lowest leakage
    wire [26:0]	DSP_D = (USE_D == "TRUE") ? { d_i[25], d_i } : {27{1'b1}};   
    wire [17:0] DSP_B = b_i;
    // if we're subtracting, we need to flip C
    wire [47:0] DSP_C = (USE_C == "TRUE") ? ((SUBTRACT_C == "TRUE") ? ~c_i : c_i) : {48{1'b1}} ;        
    // and if we're subtracting C, we need to pass 1 to carryin to handle the two's complement
    wire CARRYIN = (SUBTRACT_C == "TRUE") ? 1 : ((USE_CARRYIN == "TRUE") ? carryin_i : 1'b0 );
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
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .ACIN( acin_i ),
                                    .ACOUT( acout_o ),
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(ALUMODE));		  
               end else begin : APCSCIN // block: ABPCSCIN
		// A, P have cascade inputs
		(* CUSTOM_CC_DST = CLKTYPE *)
		DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .ACIN( acin_i ),
                                    .ACOUT( acout_o ),
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
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
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT( acout_o ),
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(ALUMODE));                
	       end else begin : PCSCIN // block: BPCSCIN
		// P has cascade input
		(* CUSTOM_CC_DST = CLKTYPE *)		
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT( acout_o ),
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
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
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .ACIN( acin_i ),
                                    .ACOUT(acout_o),                           
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(ALUMODE));
		end // block: ABCSCIN
	        else begin : ACSCIN
		   // A has cascade inputs
		   (* CUSTOM_CC_DST = CLKTYPE *)
                   DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "CASCADE" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .ACIN( acin_i ),
                                    .ACOUT(acout_o),                           
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
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
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT(acout_o),
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(ALUMODE));
		end // block: BCSCIN
	        else begin : NCSCIN
		   // No one has cascade inputs
		(* CUSTOM_CC_DST = CLKTYPE *)
                DSP48E2 #( .ACASCREG( MY_ACASCREG ),
                           .A_INPUT( "DIRECT" ),
                           .ADREG( ADREG ),
                           .ALUMODEREG(1'b0),
                           .AREG(DSP_AREG),
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
			   .RND(RND_VAL),
			               .USE_PATTERN_DETECT(USE_PATTERN_DETECT),
			               .SEL_PATTERN(SEL_PATTERN),
			               .PATTERN(PATTERN),
			               .MASK(MASK),
                           .USE_MULT("MULTIPLY"))
                           u_dsp(   .A(DSP_A),
                                    .ACOUT(acout_o),
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
                                    .PCOUT(pcout_o),
                                    .INMODE(DSP_INMODE),
                                    .OPMODE(OPMODE),
                                    `RESETS( rst_i ),
                                    `CLOCK_ENABLES( ce ),
                                    .PATTERNDETECT(pattern_o),
                                    .ALUMODE(ALUMODE));
		end // block: NCSCIN	       
            end // block: NCSCIN	   
        end // block: NCSC
       
    endgenerate                                
               
endmodule
