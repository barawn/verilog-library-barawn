`timescale 1ns / 1ps
// PUEO matched filter. v2 reorganizes the filter as 4 combined
// filters more like a systolic (although it's not really systolic).
// Unlike the v1, the adders are mostly all DSPs.
//
// Output is compressed to the upper 12 bits of the range. For a
// matched impulse the gain is like ~3 (10 dB), so decent impulses
// do compress.
module matched_filter_v2 #(parameter INBITS=12,
                           parameter NSAMP=8)(
        input aclk,
        input [NSAMP*INBITS-1:0] data_i,
        output [NSAMP*INBITS-1:0] data_o
    );
    
    // the output is the filter result divided by 16
    // (downshift by 4). This gets us to "on the order of 1"
    // for the overall gain.
    localparam OUTSHIFT = 4;
    
    // Subfilters.
    wire [7:0][15:0] systA_out;
    wire [7:0][15:0] systA1_out;
    wire [7:0][15:0] systB_out;
    wire [7:0][17:0] systC_out;
    // Storage.
    wire [NSAMP-1:0][INBITS-1:0] adc_indata = data_i;
    reg [NSAMP-1:0][INBITS-1:0] adc_instore ={12*8{1'b0}};
    always @(posedge aclk) begin
        adc_instore <= adc_indata;
    end        

    generate
        genvar i;
        for (i=0;i<8;i=i+2) begin : LP
            wire [47:0] systB_to_systC;
            wire [47:0] systB_add = { {8{systA_out[i+1][15]}}, systA_out[i+1],
                                      {8{systA_out[i][15]}}, systA_out[i]};
            wire [47:0] systC_add = { {8{systA1_out[i+1][15]}}, systA1_out[i+1],
                                      {8{systA1_out[i][15]}}, systA1_out[i]};
            wire [1:0] saturation;
            wire [1:0] lsb_correct;
            reg [1:0][INBITS-1:0] sat_and_store = {2*INBITS{1'b0}};
            // systA0   B: (i-7) A: (i-4)
            systA_matched_filter_v2 #(.SUBTYPE(0),
                                      .INBITS(12))
                                       u_systA0(.clk_i(aclk),
                .inA0_i( i < 4 ? adc_instore[i+4] : adc_indata[i-4]  ),
                .inA1_i( i+1 < 4 ? adc_instore[i+1+4] : adc_indata[i+1-4] ),
                .inB0_i( i < 7 ? adc_instore[i+1] : adc_indata[i-7]  ),
                .inB1_i( i+1 < 7 ? adc_instore[i+1+1] : adc_indata[i+1-7]),
                .out0_o( systA_out[i]   ),
                .out1_o( systA_out[i+1]   ));                    
            // systA1   B: (i-5) A: (i-3)
            systA_matched_filter_v2 #(.SUBTYPE(1),
                                      .INBITS(12))
                                       u_systA1(.clk_i(aclk),
                .inA0_i( i < 3 ? adc_instore[i+5] : adc_indata[i-3]  ),
                .inA1_i( i+1 < 3 ? adc_instore[i+1+5] : adc_indata[i+1-3] ),
                .inB0_i( i < 5 ? adc_instore[i+3] : adc_indata[i-5]  ),
                .inB1_i( i+1 < 5 ? adc_instore[i+1+3] : adc_indata[i+1-5]),
                .out0_o( systA1_out[i]   ),
                .out1_o( systA1_out[i+1]   ));                    
            // systB    B: (i-6) A: (i-2)
            systB_matched_filter_v2 #(.INBITS(12))
                                     u_systB(.clk_i(aclk),
                .inA0_i( i < 2 ? adc_instore[i+6]   : adc_indata[i-2] ),
                .inA1_i( i+1<2 ? adc_instore[i+1+6] : adc_indata[i+1-2] ),
                .inB0_i( i < 6 ? adc_instore[i+2]   : adc_indata[i-6] ),
                .inB1_i( i+1<6 ? adc_instore[i+1+2] : adc_indata[i+1-6] ),
                .add_i( systB_add ),
                .pc_o(systB_to_systC),
                .out0_o( systB_out[i] ),
                .out1_o( systB_out[i+1] )); 
            // systC    B: (i-1) A: i

            // systC includes the rounding constant.
            // The output is 24 bits for each, but the actual
            // output can only range 18 bits. To saturate,
            // we need to look at [17:15] and determine if
            // [17:15] != 111 or != 000.
            // Our output has 4 fractional bits: rounding
            // involves adding 0b1000, and then if the low
            // 4 bits are all 0 the LSB gets forced to zero.
            // Since we're in SIMD mode the round constant is
            // 24'h8,24'h8
            systC_matched_filter_v2 #(.INBITS(12),
                                      .OUTBITS(18),
                                      .RND({24'h8,24'h8}),
                                      .USE_RND("TRUE"))
                                    u_systC(.clk_i(aclk),
                .inA0_i( adc_indata[i] ),
                .inA1_i( adc_indata[i+1] ),
                .inB0_i( (i<1)   ? adc_instore[i+7] : adc_indata[i-1] ),
                // this is adc_indata[i+1-1]
                .inB1_i( adc_indata[i] ),
                .add_i( systC_add ),
                .pc_i( systB_to_systC ),
                .out0_o( systC_out[i] ),
                .out1_o( systC_out[i+1] ));

            assign saturation[0] = (systC_out[i][17:15] != 3'b111 &&
                                    systC_out[i][17:15] != 3'b000);
            assign saturation[1] = (systC_out[i+1][17:15] != 3'b111 &&
                                    systC_out[i+1][17:15] != 3'b000);
            assign lsb_correct[0] = (systC_out[i][3:0] == 4'h0);
            assign lsb_correct[1] = (systC_out[i+1][3:0] == 4'h0);
            // upshift, saturate, and LSB correct for rounding
            always @(posedge aclk) begin : SS
                if (saturation[0]) begin
                    sat_and_store[0][INBITS-1] <= systC_out[i][17];
                    sat_and_store[0][0 +: (INBITS-1)] <= {(INBITS-1){~systC_out[i][17]}};
                end else begin
                    sat_and_store[0][INBITS-1] <= systC_out[i][17];
                    sat_and_store[0][1 +: (INBITS-2)] <= systC_out[i][5 +: (INBITS-2)];
                    sat_and_store[0][0] <= systC_out[i][4] && !lsb_correct[0];
                end                 

                if (saturation[1]) begin
                    sat_and_store[1][INBITS-1] <= systC_out[i+1][17];
                    sat_and_store[1][0 +: (INBITS-1)] <= {(INBITS-1){~systC_out[i+1][17]}};
                end else begin
                    sat_and_store[1][INBITS-1] <= systC_out[i+1][17];
                    sat_and_store[1][1 +: (INBITS-2)] <= systC_out[i+1][5 +: (INBITS-2)];
                    sat_and_store[1][0] <= systC_out[i+1][4] && !lsb_correct[1];
                end                 
            end
            assign data_o[INBITS*i +: INBITS] = sat_and_store[0];
            assign data_o[INBITS*(i+1) +: INBITS] = sat_and_store[1];
        end
    endgenerate        
        
endmodule
