`timescale 1ns / 1ps

module shannon_whitaker_lpfull_tb;

    wire clk;
    tb_rclk #(.PERIOD(5.0)) u_clk(.clk(clk));
    reg [11:0] samples[7:0];
    integer i;
    initial for (i=0;i<8;i=i+1) samples[i] <= 0;
    wire [12*8-1:0] sample_arr =
        { samples[7],
          samples[6],
          samples[5],
          samples[4],
          samples[3],
          samples[2],
          samples[1],
          samples[0] };
          


    wire [11:0] outsample[7:0];
    wire [11:0] outsampleB[7:0];
    wire [12*8-1:0] outsample_arr;
    wire [7:0][12:0] outsampleB_arr;
    
    reg [11:0] pretty_insample = {12{1'b0}};    
    reg [11:0] pretty_sample = {12{1'b0}};
    reg [11:0] pretty_sampleB = {12{1'b0}};
    integer pi;
    always @(posedge clk) begin
        #0.05;
        pretty_sample <= outsample[0];
        pretty_sampleB <= outsampleB[0];
        pretty_insample <= samples[0];
        for (pi=1;pi<8;pi=pi+1) begin
            #(5.0/8);
            pretty_sample <= outsample[pi];
            pretty_sampleB <= outsampleB[pi];
            pretty_insample <= samples[pi];
        end            
    end
    generate
        genvar j;
        for (j=0;j<8;j=j+1) begin : DEVEC
            assign outsample[j] = outsample_arr[12*j +: 12];
            assign outsampleB[j] = outsampleB_arr[j];
        end
    endgenerate

    reg ip_tvalid = 0;
            
    shannon_whitaker_lpfull_v2 uut( .clk_i(clk),
                                    .in_i(sample_arr),
                                    .out_o(outsample_arr));
    shannon_whitaker_lpfull_v3 uutB(.clk_i(clk),
                                    .rst_i(1'b0),
                                    .dat_i(sample_arr),
                                    .dat_o(outsampleB_arr));
    int max_val = 2047;
    int min_val = -2048;
    initial begin
        //Blast starting at the first sample
        #200;
        @(posedge clk);
        #300;
        
        @(posedge clk);
        #0.01;
        samples[0] = -2048; //b1
        samples[1] = 0;
        samples[2] = 2047;  //b3
        samples[3] = 0;
        samples[4] = -2048; //b5
        samples[5] = 0;
        samples[6] = 2047;  //b7
        samples[7] = 0;
        @(posedge clk);
        #0.01;
        samples[0] = -2048; //b9
        samples[1] = 0;
        samples[2] = 2047;  //b11
        samples[3] = 0;
        samples[4] = -2048; //b13
        samples[5] = 0;
        samples[6] = 2047;  //b15
        samples[7] = 2047;  //b16
        @(posedge clk);
        #0.01;
        samples[0] = 2047; //b15
        samples[1] = 0;
        samples[2] = -2048;  //b13
        samples[3] = 0;
        samples[4] = 2047; //b11
        samples[5] = 0;
        samples[6] = -2048;  //b9
        samples[7] = 0;
        @(posedge clk);
        #0.01;
        samples[0] = 2047; //b7
        samples[1] = 0;
        samples[2] = -2048;  //b5
        samples[3] = 0;
        samples[4] = 2047; //b3
        samples[5] = 0;
        samples[6] = -2048;  //1
        samples[7] = 0;
        @(posedge clk);
        #0.01;
        samples[0] = 0; 
        samples[1] = 0;
        samples[2] = 0;  
        samples[3] = 0;
        samples[4] = 0; 
        samples[5] = 0;
        samples[6] = 0;  
        samples[7] = 0;
        #100;
        



        // // Test each sample
        // #200;
        // @(posedge clk);
        // #300;
        
        // @(posedge clk);
        // #0.01;
        // samples[0] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[0] = 0;
        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[1] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[1] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[1] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[1] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[2] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[2] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[3] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[3] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[4] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[4] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[5] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[5] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[6] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[6] = 0;

        // #100;
        // @(posedge clk);
        // #0.01;
        // samples[7] = 1000;
        // @(posedge clk);
        // #0.01;
        // samples[7] = 0;
                    
    end    

endmodule
