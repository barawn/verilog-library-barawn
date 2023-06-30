`timescale 1ns / 1ps
`define DLYFF 1
// Module to generate phase indicators between multiple
// synchronous clocks. Can generate up to 8 different
// phase outputs with different multiples of the same
// low-frequency clock. Because we want the multiplier
// to be an integer (so no range limitations) we just
// hard code the max number of phase outputs.
//
// This module works by having a synchronizing clock
// being a common divisor of all of the clocks to sync up.
// The output phase indicator then indicates the *first*
// clock of the multiplied clocks in the new sync clock
// cycle.
//
// As an example, suppose we have
// NUM_CLK_PHASE = 3
// CLK0_MULT = 2
// CLK1_MULT = 3
// CLK2_MULT = 6
// sync_clk clk[0] phase[0] clk[1] phase[1] clk[2] phase[2]
// 1        1      1        1      1        1      1
// 1        1      1        1      1        0      1
// 1        1      1        0      1        1      0
// 1        0      1        0      1        0      0
// 1        0      1        1      0        1      0
// 1        0      1        1      0        0      0
// 0        1      0        0      0        1      0
// 0        1      0        0      0        0      0
// 0        1      0        1      0        1      0
// 0        0      0        1      0        0      0
// 0        0      0        0      0        1      0
// 0        0      0        0      0        0      0

module param_clk_phase #(
        parameter NUM_CLK_PHASE = 8,
        parameter CLK0_MULT = 2,
        parameter CLK1_MULT = 2,
        parameter CLK2_MULT = 2,
        parameter CLK3_MULT = 2,
        parameter CLK4_MULT = 2,
        parameter CLK5_MULT = 2,
        parameter CLK6_MULT = 2,
        parameter CLK7_MULT = 2
    )(
        // Synchronizing clock.
        input sync_clk_i,
        // Input clocks
        input [NUM_CLK_PHASE-1:0] clk_i,
        // Output phase indicator
        output [NUM_CLK_PHASE-1:0] phase_o
    );
    
    // The one global we have is a toggle in the sync clock domain.
    reg sync_clk_toggle = 0;
    always @(posedge sync_clk_i)
        sync_clk_toggle <= ~sync_clk_toggle;    

    // sigh. hacky-hacky.
    // Work around the fact that we can't easily declare
    // an integer array assigned to parameters.
    function integer clk_mult_lookup;
        input integer idx;
        begin
            if (idx==0) clk_mult_lookup = CLK0_MULT;
            else if (idx==1) clk_mult_lookup = CLK1_MULT;
            else if (idx==2) clk_mult_lookup = CLK2_MULT;
            else if (idx==3) clk_mult_lookup = CLK3_MULT;
            else if (idx==4) clk_mult_lookup = CLK4_MULT;
            else if (idx==5) clk_mult_lookup = CLK5_MULT;
            else if (idx==6) clk_mult_lookup = CLK6_MULT;
            else clk_mult_lookup = CLK7_MULT;
        end 
    endfunction
    
    generate
        genvar i;
        for (i=0;i<NUM_CLK_PHASE;i=i+1) begin : LP
            // Reregister toggle in the faster domain.
            reg [clk_mult_lookup(i)-1:0] clk_sync = {clk_mult_lookup(i){1'b0}};
            // Phase tracking registers.
            reg [clk_mult_lookup(i)-1:0] clk_phase = {clk_mult_lookup(i){1'b0}};
            
            always @(posedge clk_i[i]) begin
                clk_sync <= { clk_sync[clk_mult_lookup(i)-2:0], sync_clk_toggle};
                // This isn't the method that I've used before but it
                // should still work. Simplifies the fanout of the clk_sync
                // conditional. Could lead to goofiness if the clock changes but
                // it'd resolve, and that behavior's always iffy anyway.
                // Also gets rid of the clk_phase buffering, since it's already
                // buffered.
                clk_phase[0] <= (clk_sync[clk_mult_lookup(i)-2] ^ clk_sync[clk_mult_lookup(i)-1]);
                clk_phase[clk_mult_lookup(i)-1:1] <= clk_phase[clk_mult_lookup(i)-2:0];
            end
            
            assign phase_o[i] = clk_phase[clk_mult_lookup(i)-1];
        end
    endgenerate                  
endmodule
