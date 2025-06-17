`timescale 1ns / 1ps
`include "dsp_macros.vh"
// DSP portion of the dual pueo beam module
// as well as an 18-bit threshold loadable individually and with common update.
//
// Passes basic unit tests: Lucas 5/12/2025

// `define USING_DEBUG 1
`define DEBUG_SAMPLES 10000
`define DEBUG_IGNORE_SAMPLES 150

module dual_pueo_beam_dsp #(parameter WBCLKTYPE = "PSCLK", parameter CLKTYPE = "ACLK")(
        input clk_i,
        input [16:0] beamA_in0_i,
        input [16:0] beamA_in1_i,
        input [16:0] beamB_in0_i,
        input [16:0] beamB_in1_i,
        
        
        input [17:0] thresh_i,
        input [1:0] thresh_ce_i,
        input update_i, // This may be redundant
        
        output [1:0] trigger_o
    );
    
    // Bit tracking.
    // DSP A handles the combine.
    // {A[5:0], B[17:0] } = { {7{1'b0}}, beamA_in0_i }
    // {A[29:6]} = { {7{1'b0}}, beamB_in0_i }
    // C[23:0] = { {7{1'b0}}, beamA_in1_i }
    // C[47:24] = { {7{1'b0}},beamB_in1_i }
    //
    // DSP B handles the FIR portion and the threshold.
    // DSP A computes -(beamA_sum + beamA_carry*2) = -T
    // DSP B computes thresh+(-T)+(-Tz^-1) or thresh-(T+Tz^-1).
    // P[47] and P[23] then correspond to the trigger. Note that thresh is
    // exclusive (trigger is (T+Tz^-1) > thresh)
    // for instance, if thresh = 80,000 = 1_3880
    // beamA_in0 = 20,000
    // beamA_in1 = 20,000
    // -T would be FF_63C0
    // next clock if they're the same, we have
    // 01_3880 + FF_63C0 + FF_63C0 = 00_0000 (trig = 0)
    // however if next clock it was
    // beamA_in0 = 20,001
    // beamA_in1 = 20,000
    // -T would be FF_63BF
    // and we would have
    // 01_3880 + FF63C0 + FF_36BF = FF_FFFF (trig = 1)
    //
    // Note that we do not look at the carry bit because we're doing a 3-input
    // add in the second DSP.
    
    // DSPA computes AB + C = (in0 + in1)
    wire [47:0] dspA_ab = { {7{1'b0}}, beamA_in0_i,  {7{1'b0}}, beamB_in0_i };
    wire [29:0] dspA_a = `DSP_AB_A( dspA_ab );
    wire [17:0] dspA_b = `DSP_AB_B( dspA_ab );
    wire [47:0] dspA_c =  { {7{1'b0}}, beamA_in1_i,  {7{1'b0}}, beamB_in1_i };
    wire [47:0] dspA_to_dspB;
    wire [47:0] dspA_p;
     
    // this is so amazingly sleazy
    wire [3:0] dspA_alumode = `ALUMODE_Z_MINUS_XYCIN;
    // it goes W, Z, Y, X
    wire [8:0] dspA_opmode = { 2'b00, `Z_OPMODE_0, `Y_OPMODE_C, `X_OPMODE_AB };
    wire [4:0] dspA_inmode = {5{1'b0}};
    wire [2:0] dspA_carryinsel = `CARRYINSEL_CARRYIN;

    // dspB takes in the threshold into AB, and dspA_p into C   
    wire [47:0] dspB_ab = { {6{1'b0}}, thresh_i, {6{1'b0}}, thresh_i };
    wire [29:0] dspB_a = `DSP_AB_A( dspB_ab );
    wire [17:0] dspB_b = `DSP_AB_B( dspB_ab );
    wire [47:0] dspB_p;

    wire [3:0] dspB_alumode = `ALUMODE_SUM_ZXYCIN;
    wire [8:0] dspB_opmode = { 2'b00, `Z_OPMODE_PCIN, `Y_OPMODE_C, `X_OPMODE_AB };
    wire [4:0] dspB_inmode = {5{1'b0}};
    wire [2:0] dspB_carryinsel = `CARRYINSEL_CARRYIN;


    (* CUSTOM_CC_DST = CLKTYPE *)
    DSP48E2 #(`NO_MULT_ATTRS, `DE2_UNUSED_ATTRS,`CONSTANT_MODE_ATTRS,
              .AREG(1),.BREG(1),.CREG(1),.PREG(1),
              .USE_SIMD("TWO24"))
              u_dspA( .CLK(clk_i),
                      .A( dspA_a ),
                      .CEA2(1'b1),
                      .RSTA(1'b0),
                      .B( dspA_b ),
                      .CEB2(1'b1),
                      .RSTB(1'b0),
                      .C( dspA_c ),
                      .CEC(1'b1),
                      .RSTC(1'b0),
                      .CEP(1'b1),
                      .P(dspA_p),
                      .PCOUT(dspA_to_dspB),
                      .RSTP(1'b0),
                      .ALUMODE(dspA_alumode),
                      .INMODE(dspA_inmode),
                      .OPMODE(dspA_opmode),
                      .CARRYINSEL(dspA_carryinsel),
                      .CARRYIN(1'b0));
   
    (* CUSTOM_CC_DST = CLKTYPE *)
    DSP48E2 #(`NO_MULT_ATTRS, `DE2_UNUSED_ATTRS,`CONSTANT_MODE_ATTRS,
              .AREG(2),.BREG(2),.CREG(1),
              .USE_SIMD("TWO24"))
              u_dspB( .CLK(clk_i),
                      .A( dspB_a ),
                      .CEA1(thresh_ce_i[0]),
                      .CEA2(update_i), 
                      .RSTA(1'b0),
                      .B( dspB_b ),
                      .CEB1(thresh_ce_i[1]),
                      .CEB2(update_i),
                      .RSTB(1'b0),
                      .C( dspA_p ),
                      .CEC(1'b1),
                      .RSTC(1'b0),
                      .CEP(1'b1),
                      .P(dspB_p),
                      .PCIN(dspA_to_dspB),
                      .RSTP(1'b0),
                      .ALUMODE(dspB_alumode),
                      .INMODE(dspB_inmode),
                      .OPMODE(dspB_opmode),
                      .CARRYINSEL(dspB_carryinsel),
                      .CARRYIN(1'b0));

`ifdef USING_DEBUG
    // Debugging only
    int fout = $fopen($sformatf("freqs/sumsquare_pulse.dat"),"w");
    int counter = -1 * `DEBUG_IGNORE_SAMPLES;
    reg signed [23:0] debugdata;
    always @(posedge clk_i) begin : DEBUG_WRITEOUT
        debugdata = dspA_to_dspB[23:0];
        if(counter < 0) begin
                $display($sformatf("Ignoring %1d", debugdata));
                counter++;
        end else if(counter<`DEBUG_SAMPLES) begin
                $display($sformatf("%1d\n",debugdata));
                $fwrite(fout,$sformatf("%1d\n",debugdata));
                counter++;
        end else if(counter==`DEBUG_SAMPLES) begin
                $fclose(fout);
                counter=`DEBUG_SAMPLES+1;
        end
    end
`endif
    // These look swapped so that 0 corresponds to A and 1 to B
    assign trigger_o[0] = dspB_p[47];
    assign trigger_o[1] = dspB_p[23];              
    
endmodule
