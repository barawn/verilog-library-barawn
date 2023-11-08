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
    wire [12*8-1:0] outsample_arr;
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
        end
    endgenerate
        
    shannon_whitaker_lpfull uut(.clk_i(clk),
                                .in_i(sample_arr),
                                .out_o(outsample_arr));

    initial begin
        #500;
        @(posedge clk);
        #0.01;
        samples[0] = 1000;
        @(posedge clk);
        #0.01;
        samples[0] = 0;
    end    

endmodule
