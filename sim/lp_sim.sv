`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/04/2025 10:21:29 PM
// Design Name: 
// Module Name: lp_sim
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module lp_sim;

    wire clk;
    tb_rclk #(.PERIOD(2.667)) u_clk(.clk(clk));

    reg [1:0] clk_phase = {2{1'b0}};
    wire this_clk_phase = clk_phase == 2'b00;
    always @(posedge clk) begin
        if (clk_phase == 2'b10) clk_phase <= #0.01 2'b00;
        else clk_phase <= #0.01 clk_phase + 1;
    end

    reg [11:0] pretty_insample = {12{1'b0}};    
    reg [12:0] pretty_outsample = {13{1'b0}};    
    reg [11:0] pretty_upsample = {12{1'b0}};
    
    reg [7:0][11:0] adc_indata = {96{1'b0}};
    wire [47:0] tmp_out;

    wire [3:0][11:0] adc_indata1500 = { adc_indata[6],
                                        adc_indata[4],
                                        adc_indata[2],
                                        adc_indata[0] };

    reg rst = 0;
    wire [7:0][12:0] filt0_out;

    wire [3:0][12:0] filt1_out;

    wire [7:0][11:0] ups_data;

    reg [7:0][11:0] adc_indata_hold = {96{1'b0}};
    reg [7:0][12:0] filt1_out_hold = {4*13{1'b0}};
    reg [7:0][11:0] ups_out_hold = {96{1'b0}};
    always @(posedge clk) begin
        adc_indata_hold <= #0.001 adc_indata;
        filt1_out_hold <= #0.001 filt1_out;
        ups_out_hold <= #0.001 ups_data;
    end        

    always @(posedge clk) begin
        #0.002 pretty_insample <= adc_indata_hold[0];
        #0.666 pretty_insample <= adc_indata_hold[2];
        #0.666 pretty_insample <= adc_indata_hold[4];
        #0.666 pretty_insample <= adc_indata_hold[6];
    end

    always @(posedge clk) begin
        #0.002 pretty_outsample <= filt1_out_hold[0];
        #0.666 pretty_outsample <= filt1_out_hold[1];
        #0.666 pretty_outsample <= filt1_out_hold[2];
        #0.666 pretty_outsample <= filt1_out_hold[3];
    end

    always @(posedge clk) begin
        #0.002 pretty_upsample <= ups_out_hold[0];
        #0.333 pretty_upsample <= ups_out_hold[1];
        #0.333 pretty_upsample <= ups_out_hold[2];
        #0.333 pretty_upsample <= ups_out_hold[3];
        #0.333 pretty_upsample <= ups_out_hold[4];
        #0.333 pretty_upsample <= ups_out_hold[5];
        #0.333 pretty_upsample <= ups_out_hold[6];
        #0.333 pretty_upsample <= ups_out_hold[7];
    end

    wire [7:0][11:0] mf_out;
    wire [3:0][11:0] mf2_out;
//    wire [7:0][15:0] systA_out;
//    wire [7:0][15:0] systA1_out;
//    wire [7:0][15:0] systB_out;
//    wire [7:0][15:0] systC_out;
//    // ok need to think here:
//    // systA in the matched filter corresponds to samples 0/3 (subtype 0)
//    // and samples 2/4 (subtype 1) when generating sample 7.
//    // Index rotation means:
//    //              subtype 0       subtype 1
//    // sample 7     0       3       2       4
//    // sample 6     7z^-1   2       1       3
//    // sample 5     6z^-1   1       0       2
//    // sample 4     5z^-1   0       7z^-1   1
//    // sample 3     4z^-1   7z^-1   6z^-1   0
//    // sample 2     3z^-1   6z^-1   5z^-1   7z^-1
//    // sample 1     2z^-1   5z^-1   4z^-1   6z^-1
//    // sample 0     1z^-1   4z^-1   3z^-1   5z^-1
//    // a half-and-half could nominally help if we instead did 0/3 and 2/5?
//    // that's not half bad but we'll think about that later

//    // gwwaaaar must. think. about. this.
//    //
//    // If we excite sample 7
//    // what we WANT are FUTURE patterns:
//    // so 7     0   1   2   3   4   5   6
//    //    CA    CB  BA A1A  A0A A1B  BB A0B
//    //   -1     -1  0   0   0   1   1   0
//    //    0     -1  -1  -1  0   1   1   1
//    //    1     0   -1  -1  -1  0   1   2
//    //    1     0   -1  -2  -2  0   2   4
//    //    0     -4  -4   1  4   1   -2  -1
//    //    1     1
//    //
//    //  so if we crafted a waveform for sample 7 we would have
//    //  systC B:                A: adc_indata[7]    sample 7
//    //  systC B: adc_instore[7] A:                  sample 0
//    //  systB                   A: adc_instore[7]   sample 1
//    // systA1 B:                A: adc_instore[7]   sample 2
//    // systA0 B:                A: adc_instore[7]   sample 3
//    // systA1 B: adc_instore[7] A:                  sample 4
//    //  systB B: adc_instore[7] A:                  sample 5
//    // systA0 B: adc_instore[7] A:                  sample 6
//    //
//    // rotate samples: excite 6 and we have
//    //  systC B:                A: adc_indata[6]    sample 6
//    //  systC B: adc_indata[6]  A:                  sample 7
//    //  systB                   A: adc_instore[6]   sample 0
//    // systA1 B:                A: adc_instore[6]   sample 1
//    // systA0 B:                A: adc_instore[6]   sample 2
//    // systA1 B: adc_instore[6] A:                  sample 3
//    //  systB B: adc_instore[6] A:                  sample 4
//    // systA0 B: adc_instore[6] A:                  sample 5
//    //
//    // rotate samples: excite 5 and we have
//    //  systC B:                A: adc_indata[5]    sample 5
//    //  systC B: adc_indata[5]  A:                  sample 6
//    //  systB                   A: adc_indata[5]    sample 7
//    // systA1 B:                A: adc_instore[5]   sample 0
//    // systA0 B:                A: adc_instore[5]   sample 1
//    // systA1 B: adc_instore[5] A:                  sample 2
//    //  systB B: adc_instore[5] A:                  sample 3
//    // systA0 B: adc_instore[5] A:                  sample 4
//    //
//    // rotate samples: excite 4 and we have
//    //  systC B:                A: adc_indata[4]    sample 4
//    //  systC B: adc_indata[4]  A:                  sample 5
//    //  systB                   A: adc_indata[4]    sample 6
//    // systA1 B:                A: adc_indata[4]    sample 7
//    // systA0 B:                A: adc_instore[4]   sample 0
//    // systA1 B: adc_instore[4] A:                  sample 1
//    //  systB B: adc_instore[4] A:                  sample 2
//    // systA0 B: adc_instore[4] A:                  sample 3
//    //
//    // rotate samples: excite 3 and we have
//    //  systC B:                A: adc_indata[3]    sample 3
//    //  systC B: adc_indata[3]  A:                  sample 4
//    //  systB                   A: adc_indata[3]    sample 5
//    // systA1 B:                A: adc_indata[3]    sample 6
//    // systA0 B:                A: adc_indata[3]    sample 7
//    // systA1 B: adc_instore[3] A:                  sample 0
//    //  systB B: adc_instore[3] A:                  sample 1
//    // systA0 B: adc_instore[3] A:                  sample 2
//    //
//    // rotate samples: excite 2 and we have
//    //  systC B:                A: adc_indata[2]    sample 2
//    //  systC B: adc_indata[2]  A:                  sample 3
//    //  systB                   A: adc_indata[2]    sample 4
//    // systA1 B:                A: adc_indata[2]    sample 5
//    // systA0 B:                A: adc_indata[2]    sample 6
//    // systA1 B: adc_indata[2]  A:                  sample 7
//    //  systB B: adc_instore[2] A:                  sample 0
//    // systA0 B: adc_instore[2] A:                  sample 1
//    //
//    // rotate samples: excite 1 and we have
//    //  systC B:                A: adc_indata[1]    sample 1
//    //  systC B: adc_indata[1]  A:                  sample 2
//    //  systB                   A: adc_indata[1]    sample 3
//    // systA1 B:                A: adc_indata[1]    sample 4
//    // systA0 B:                A: adc_indata[1]    sample 5
//    // systA1 B: adc_indata[1]  A:                  sample 6
//    //  systB B: adc_indata[1]  A:                  sample 7
//    // systA0 B: adc_instore[1] A:                  sample 0
//    //
//    // rotate samples: excite 0 and we have
//    //  systC B:                A: adc_indata[0]    sample 0
//    //  systC B: adc_indata[0]  A:                  sample 1
//    //  systB                   A: adc_indata[0]    sample 2
//    // systA1 B:                A: adc_indata[0]    sample 3
//    // systA0 B:                A: adc_indata[0]    sample 4
//    // systA1 B: adc_indata[5]  A:                  sample 5
//    //  systB B: adc_indata[5]  A:                  sample 6
//    // systA0 B: adc_indata[5]  A:                  sample 7
//    //
//    // NOW MERGE
//    //  systC B: adc_indata[6]  A: adc_indata[7]    sample 7
//    //  systC B: adc_instore[7] A: adc_indata[0]    sample 0
//    //  systB B: adc_instore[3] A: adc_instore[7]   sample 1
//    // systA1 B: adc_instore[5] A: adc_instore[7]   sample 2
//    // systA0 B: adc_instore[4] A: adc_instore[7]   sample 3
//    // systA1 B: adc_instore[7] A:                  sample 4
//    //  systB B: adc_instore[7] A:                  sample 5
//    // systA0 B: adc_instore[7] A:                  sample 6
    
//    // systC is B: (i+7)%8 A: i
//    // systB is B: (i+2)%8 A: (i+6)%8
//    // systA1 is B: (i+3)%8 A: (i+5)%8
//    // systA0 is B: (i+1)%8 A: (i+4)%8
//    //
//    // but when do we grab stores??
//    // these are really subtractions:
//    // systC    B: (i-1) A: i
//    // systB    B: (i-6) A: (i-2)
//    // systA1   B: (i-5) A: (i-3)
//    // systA0   B: (i-7) A: (i-4)
//    // so this should make it obvious
//    // so sample 7 is
//    // systC    B: 6    A: 7
//    // systB    B: 1    A: 5
//    // systA1   B: 2    A: 4
//    // systA0   B: 0    A: 3
//    // and sample 6 is
//    // systC    B: 5        A: 6
//    // systB    B: 0        A: 4
//    // systA1   B: 1        A: 3
//    // systA0   B: 7z^-1    A: 2
    
//    reg [7:0][11:0] adc_instore ={12*8{1'b0}};
//    reg [7:0][11:0] adc_instore2 = {12*8{1'b0}};

//    always @(posedge clk) begin
//        adc_instore <= adc_indata;
//        adc_instore2 <= adc_instore;
//    end        

//    // OK, so let's try ALL of them
//    generate
//        genvar i;
//        for (i=0;i<8;i=i+2) begin : LP
//            wire [47:0] systB_to_systC;
//            wire [47:0] systB_add = { {8{systA_out[i+1][15]}}, systA_out[i+1],
//                                      {8{systA_out[i][15]}}, systA_out[i]};
//            wire [47:0] systC_add = { {8{systA1_out[i+1][15]}}, systA1_out[i+1],
//                                      {8{systA1_out[i][15]}}, systA1_out[i]};
//            // systA0   B: (i-7) A: (i-4)
//            systA_matched_filter_v2 #(.SUBTYPE(0),
//                                      .INBITS(12))
//                                       uutB(.clk_i(clk),
//                .inA0_i( i < 4 ? adc_instore[i+4] : adc_indata[i-4]  ),
//                .inA1_i( i+1 < 4 ? adc_instore[i+1+4] : adc_indata[i+1-4] ),
//                .inB0_i( i < 7 ? adc_instore[i+1] : adc_indata[i-7]  ),
//                .inB1_i( i+1 < 7 ? adc_instore[i+1+1] : adc_indata[i+1-7]),
//                .out0_o( systA_out[i]   ),
//                .out1_o( systA_out[i+1]   ));                    
//            // systA1   B: (i-5) A: (i-3)
//            systA_matched_filter_v2 #(.SUBTYPE(1),
//                                      .INBITS(12))
//                                       uutC(.clk_i(clk),
//                .inA0_i( i < 3 ? adc_instore[i+5] : adc_indata[i-3]  ),
//                .inA1_i( i+1 < 3 ? adc_instore[i+1+5] : adc_indata[i+1-3] ),
//                .inB0_i( i < 5 ? adc_instore[i+3] : adc_indata[i-5]  ),
//                .inB1_i( i+1 < 5 ? adc_instore[i+1+3] : adc_indata[i+1-5]),
//                .out0_o( systA1_out[i]   ),
//                .out1_o( systA1_out[i+1]   ));                    
//            // systB    B: (i-6) A: (i-2)
//            systB_matched_filter_v2 #(.INBITS(12))
//                                     uutD(.clk_i(clk),
//                .inA0_i( i < 2 ? adc_instore[i+6]   : adc_indata[i-2] ),
//                .inA1_i( i+1<2 ? adc_instore[i+1+6] : adc_indata[i+1-2] ),
//                .inB0_i( i < 6 ? adc_instore[i+2]   : adc_indata[i-6] ),
//                .inB1_i( i+1<6 ? adc_instore[i+1+2] : adc_indata[i+1-6] ),
//                .add_i( systB_add ),
//                .pc_o(systB_to_systC),
//                .out0_o( systB_out[i] ),
//                .out1_o( systB_out[i+1] )); 
//            // systC    B: (i-1) A: i
//            systC_matched_filter_v2 #(.INBITS(12))
//                                    uutE(.clk_i(clk),
//                .inA0_i( adc_indata[i] ),
//                .inA1_i( adc_indata[i+1] ),
//                .inB0_i( (i<1)   ? adc_instore[i+7] : adc_indata[i-1] ),
//                // this is adc_indata[i+1-1]
//                .inB1_i( adc_indata[i] ),
//                .add_i( systC_add ),
//                .pc_i( systB_to_systC ),
//                .out0_o( systC_out[i] ),
//                .out1_o( systC_out[i+1] ));

//        end
//    endgenerate        

//    // systA/systB need to take their data delayed a clock
    
//    // systA0   B: 0        A: 3
//    // systA0   B: 7z^-1    A: 2
//    systA_matched_filter_v2 #(.SUBTYPE(0),
//                              .INBITS(12))
//                               uutB(.clk_i(clk),
//                                    .inA0_i( adc_indata[3]  ),
//                                    .inA1_i( adc_indata[2]  ),
//                                    .inB0_i( adc_indata[0]  ),
//                                    .inB1_i( adc_instore[7] ),
//                                    .out0_o( systA_out[7]   ),
//                                    .out1_o( systA_out[6]   ));

//    // systA1   B: 2        A: 4
//    // systA1   B: 1        A: 3
//    systA_matched_filter_v2 #(.SUBTYPE(1),
//                              .INBITS(12))
//                              uutC(.clk_i(clk),
//                                   .inA0_i( adc_indata[4]   ),
//                                   .inA1_i( adc_indata[3]   ),
//                                   .inB0_i( adc_indata[2]   ),
//                                   .inB1_i( adc_indata[1]   ),
//                                   .out0_o( systA1_out[7]   ),
//                                   .out1_o( systA1_out[6]   ));
    // systB corresponds to 
    // [ 1   0 ]
    // [ 1  -1 ] 
    // [ 1  -1 ]
    // [ 2  -1 ]
    // [-2  -4 ]
    // which are samples 1 (B) and 5 (A) for sample 7
    // and samples 0 (B) and 4 (A) for sample 6

    // systB's add_i is one of the two systAs.        
//    wire [47:0] systB_to_systC;
//    wire [47:0] systB_add = { {8{systA_out[6][15]}}, systA_out[6],
//                              {8{systA_out[7][15]}}, systA_out[7] };

//    // systB    B: 1        A: 5
//    // systB    B: 0        A: 4
//    systB_matched_filter_v2 #(.INBITS(12))
//                             uutD(.clk_i(clk),
//                                  .inA0_i( adc_indata[5] ),
//                                  .inA1_i( adc_indata[4] ),
//                                  .inB0_i( adc_indata[1] ),
//                                  .inB1_i( adc_indata[0] ),
//                                  .add_i( systB_add ),
//                                  .pc_o(systB_to_systC),
//                                  .out0_o( systB_out[7] ),
//                                  .out1_o( systB_out[6] ));

    // systC has
    // [ -1  -1 ]
    // [ -1   0 ] 
    // [  0   1 ]
    // [  0  -1 ]
    // [ -4   0 ]
    // [  1   1 ]

    // systC    B: 6        A: 7
    // systC    B: 5        A: 6
//    systC_matched_filter_v2 #(.INBITS(12))
//                             uutE(.clk_i(clk),
//                                  .inA0_i( adc_indata[7] ),
//                                  .inA1_i( adc_indata[6] ),
//                                  .inB0_i( adc_indata[6] ),
//                                  .inB1_i( adc_indata[5] ),
//                                  .add0_i( systA1_out[7] ),
//                                  .add1_i( systA1_out[6] ),
//                                  .pc_i( systB_to_systC ),
//                                  .out0_o( systC_out[7] ),
//                                  .out1_o( systC_out[6] ));

    matched_filter_v2 #(.INBITS(12))
                               mf(.aclk(clk),
                                  .data_i(adc_indata),
                                  .data_o(mf_out));

    matched_filter_v3_1500 #(.INBITS(12))
                               mf2(.aclk(clk),
                                   .data_i(adc_indata1500),
                                   .data_o(mf2_out));
                                               
    shannon_whitaker_lpfull_v3 #(.INBITS(12))
                               uut(.clk_i(clk),
                                   .rst_i(rst),
                                   .dat_i(adc_indata),
                                   .dat_o(filt0_out));

    twothirds_lpfull #(.INBITS(12))
        twothirds(.clk_i(clk),
                  .clk_phase_i(this_clk_phase),
                  .rst_i(rst),
                  .dat_i({ adc_indata[6],
                           adc_indata[4],
                           adc_indata[2],
                           adc_indata[0] }),
                  .dat_o(filt1_out));

    upsample_wrap ups(.clk_i(clk),
                      .data_i({ adc_indata[6],
                           adc_indata[4],
                           adc_indata[2],
                           adc_indata[0] }),
                      .data_o(ups_data));

    initial begin
        #100;
        @(posedge clk);
        #0.1 adc_indata[6] = 16'd1000;
//             adc_indata[4] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[6] = 16'd0;
//             adc_indata[4] = 16'd0;
        #100;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd1000;
//             adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
//             adc_indata[2] = 16'd0;
        #100;
        @(posedge clk);
        #0.1 adc_indata[1] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[1] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[3] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[3] = 16'd0;

        #100;
        @(posedge clk);
        #0.1 adc_indata[4] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[4] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[5] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[5] = 16'd0;
        
        #100;
        @(posedge clk);
        #0.1 adc_indata[7] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[7] = 16'd0;

        #100;
        // timing check the systA filter:
        // if we excite both 0 and 2 at the same time 6 and 7 should
        // show the matched filter
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd1000;
             adc_indata[2] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
             adc_indata[2] = 16'd0;
        // timing check the subtype 1 filter
        // excite both 2 and 3 at the same time
        #100;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd1000;
             adc_indata[3] = 16'd1000;
        @(posedge clk);
        #0.1 adc_indata[2] = 16'd0;
             adc_indata[3] = 16'd0;   
        #100;
        // 100 MHz sine wave for the 2/3rds filter
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
             adc_indata[2] = 16'd407;
             adc_indata[4] = 16'd743;
             adc_indata[6] = 16'd951;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd994;
             adc_indata[2] = 16'd866;
             adc_indata[4] = 16'd588;
             adc_indata[6] = 16'd208;
        @(posedge clk);
        #0.1 adc_indata[0] = -16'd208;
             adc_indata[2] = -16'd588;
             adc_indata[4] = -16'd866;
             adc_indata[6] = -16'd994;
        @(posedge clk);
        #0.1 adc_indata[0] = -16'd951;
             adc_indata[2] = -16'd743;
             adc_indata[4] = -16'd407;
             adc_indata[6] = 16'd0;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd407;
             adc_indata[2] = 16'd743;
             adc_indata[4] = 16'd951;
             adc_indata[6] = 16'd994;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd866;
             adc_indata[2] = 16'd588;
             adc_indata[4] = 16'd208;
             adc_indata[6] = -16'd208;
        @(posedge clk);
        #0.1 adc_indata[0] = -16'd588;
             adc_indata[2] = -16'd866;
             adc_indata[4] = -16'd994;
             adc_indata[6] = -16'd951;
        @(posedge clk);
        #0.1 adc_indata[0] = -16'd743;
             adc_indata[2] = -16'd407;
             adc_indata[4] = 16'd0;
             adc_indata[6] = 16'd0;
        @(posedge clk);
        #0.1 adc_indata[0] = 16'd0;
             adc_indata[2] = 16'd0;
             adc_indata[4] = 16'd0;
             adc_indata[6] = 16'd0;             
    end

endmodule
