`timescale 1ns/1ps
`define DLYFF #1
`include "dsp_macros.vh"

// Dual counters using a single DSP in SIMD mode, 24 bits each.
// This honestly is just a convenience module just instantiating
// the DSP with all the right attributes and connections,
// there's literally nothing in here except the DSP.
//
// PIPELINE_INPUT reregisters the increment input.
// overflow indicates that the counter just rolled over.
// increment[0] corresponds to count[23:0] and carry[0]
// increment[1] corresponds to count[47:24] and carry[1]
module dual_dsp_counters #(parameter PIPELINE_INPUT="TRUE")
                        ( input         clk,
			  input 	rst,
			  input [1:0] 	increment,
			  output [1:0]  overflow,
			  output [47:0] count );
   wire [6:0] count_opmode = { `Z_OPMODE_P,
			       `Y_OPMODE_C,
			       `X_OPMODE_0 };   
   
   wire [47:0] count_c_in = { {23{1'b0}}, increment[1],
			      {23{1'b0}}, increment[0] };
   wire [3:0]  carryout;

   assign overflow[0] = carryout[`DUAL_DSP_CARRY0];   
   assign overflow[1] = carryout[`DUAL_DSP_CARRY1];   
   
   
   // Opmode is always ALUMODE_SUM_ZXYCIN
   DSP48E1 #(`A_UNUSED_ATTRS,
	     `B_UNUSED_ATTRS,
	     `D_UNUSED_ATTRS,
	     `NO_MULT_ATTRS,
	     `CONSTANT_MODE_ATTRS,
	     .PREG(1'b1),
	     .CREG(PIPELINE_INPUT=="TRUE"),
	     .CARRYINREG(1'b0),
	     .USE_SIMD("TWO24"),
	     .USE_PATTERN_DETECT("NO_PATDET"))
          count_dsp( `D_UNUSED_PORTS,
		     `A_UNUSED_PORTS,
		     `B_UNUSED_PORTS,
		     .CLK(clk),
		     .ALUMODE(`ALUMODE_SUM_ZXYCIN),
		     .OPMODE(count_opmode),
		     .CARRYINSEL( `CARRYINSEL_CARRYIN ),
		     .INMODE(1'b0),
		     .CARRYIN(1'b0),
		     .CECARRYIN(1'b0),
		     .RSTALLCARRYIN(1'b0),
		     .C(count_c_in),
		     .CEC(1'b1),
		     .CEP(1'b1),
		     .RSTP(rst),
		     .CARRYOUT(carryout),
		     .P(count));		     
		     
   
endmodule // dual_dsp_counters

   
