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

    wire [16*8-1:0] ip_sample_arr =
        { {{4{samples[7][11]}}, samples[7] },
          {{4{samples[6][11]}}, samples[6] },
          {{4{samples[5][11]}}, samples[5] },
          {{4{samples[4][11]}}, samples[4] },
          {{4{samples[3][11]}}, samples[3] },
          {{4{samples[2][11]}}, samples[2] },
          {{4{samples[1][11]}}, samples[1] },
          {{4{samples[0][11]}}, samples[0] } };
          


    wire [11:0] outsample[7:0];
    wire [11:0] outsampleB[7:0];
    wire [12*8-1:0] outsample_arr;
    wire [16*8-1:0] outsampleB_arr;
    
    reg [11:0] pretty_insample = {12{1'b0}};    
    reg [11:0] pretty_sample = {12{1'b0}};
    integer pi;
    always @(posedge clk) begin
        #0.05;
        pretty_sample <= outsample[0];
        pretty_insample <= samples[0];
        for (pi=1;pi<8;pi=pi+1) begin
            #(5.0/8);
            pretty_sample <= outsample[pi];
            pretty_insample <= samples[pi];
        end            
    end
    generate
        genvar j;
        for (j=0;j<8;j=j+1) begin : DEVEC
            assign outsample[j] = outsample_arr[12*j +: 12];
            assign outsampleB[j] = outsampleB_arr[16*j +: 12];
        end
    endgenerate

    reg ip_tvalid = 0;
            
    shannon_whitaker_lpfull_v2 uut(.clk_i(clk),
                                .in_i(sample_arr),
                                .out_o(outsample_arr));
    fir_compiler_lpf_copy uutB(.aclk(clk),
                               .s_axis_data_tdata(ip_sample_arr),
                               .s_axis_data_tvalid(ip_tvalid),
                               .m_axis_data_tdata(outsampleB_arr),
                               .m_axis_data_tready(1'b1));

    // 30 samples in 11 periods
    // note that the second half will just be sign flipped
    wire [11:0] sine_1100[29:0];
    assign sine_1100[0] = 0;
    assign sine_1100[1] = 743;
    assign sine_1100[2] = -995;
    assign sine_1100[3] = 588;
    assign sine_1100[4] = 208;
    assign sine_1100[5] = -866;
    assign sine_1100[6] = 951;
    assign sine_1100[7] = -407;
    // now they reverse
    assign sine_1100[8] = sine_1100[7];
    assign sine_1100[9] = sine_1100[6];
    assign sine_1100[10]= sine_1100[5];
    assign sine_1100[11]= sine_1100[4];
    assign sine_1100[12]= sine_1100[3];
    assign sine_1100[13]= sine_1100[2];
    assign sine_1100[14]= sine_1100[1];
    assign sine_1100[15]= sine_1100[0];

    assign sine_1100[16]= -1*sine_1100[1];
    assign sine_1100[17]= -1*sine_1100[2];
    assign sine_1100[18]= -1*sine_1100[3];
    assign sine_1100[19]= -1*sine_1100[4];
    assign sine_1100[20]= -1*sine_1100[5];
    assign sine_1100[21]= -1*sine_1100[6];
    assign sine_1100[22]= -1*sine_1100[7];
    assign sine_1100[23]= -1*sine_1100[8];
    assign sine_1100[24]= -1*sine_1100[9];
    assign sine_1100[25]= -1*sine_1100[10];
    assign sine_1100[26]= -1*sine_1100[11];
    assign sine_1100[27]= -1*sine_1100[12];
    assign sine_1100[28]= -1*sine_1100[13];
    assign sine_1100[29]= -1*sine_1100[14];
    
    reg [11:0] sine_samples[7:0];
    reg [23:0] counter = {24{1'b0}};
    // it's always sine_1100[8*counter % 30]
    integer ss;
    always @(posedge clk) begin
        counter <= counter + 1;
        for (ss=0;ss<8;ss=ss+1) begin
            sine_samples[ss] <= sine_1100[(8*counter+ss)% 30];
        end            
    end        
    
    integer ii,jj;
    initial begin
        #200;
        @(posedge clk);
        ip_tvalid = 1;
        #300;
        
        @(posedge clk);
        #0.01;
        samples[0] = 1000;
        @(posedge clk);
        #0.01;
        samples[0] = 0;
        #100;
        @(posedge clk);
        #0.01;
        samples[1] = 1000;
        @(posedge clk);
        #0.01;
        samples[1] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[1] = 1000;
        @(posedge clk);
        #0.01;
        samples[1] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[2] = 1000;
        @(posedge clk);
        #0.01;
        samples[2] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[3] = 1000;
        @(posedge clk);
        #0.01;
        samples[3] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[4] = 1000;
        @(posedge clk);
        #0.01;
        samples[4] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[5] = 1000;
        @(posedge clk);
        #0.01;
        samples[5] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[6] = 1000;
        @(posedge clk);
        #0.01;
        samples[6] = 0;

        #100;
        @(posedge clk);
        #0.01;
        samples[7] = 1000;
        @(posedge clk);
        #0.01;
        samples[7] = 0;
        
        // now try an 1100 MHz sine wave
        // 11 periods = 30 clocks
        // Everything repeats every 15 8-fold clocks
        // 15 8-fold clocks = 120 samples = 44 periods        
        #1000;
        
        for (ii=0;ii<1000;ii=ii+1) begin
            @(posedge clk);
            #0.01;
            for (jj=0;jj<8;jj=jj+1) begin
                samples[jj] <= sine_samples[jj];
            end
        end                
    end    

endmodule
