`timescale 1ns / 1ps
module biquad8_wrapper_tb;

    wire wbclk;
    wire aclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(aclk));

    reg wr = 0;
    reg [6:0] address = {7{1'b0}};
    reg [31:0] data = {32{1'b0}};
    wire [31:0] data_out;
    wire ack;

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

    generate
        genvar j;
        for (j=0;j<8;j=j+1) begin : DEVEC
            assign outsample[j] = outsample_arr[12*j +: 12];
        end
    endgenerate


    reg [11:0] pretty_insample = {12{1'b0}};
    reg [11:0] pretty_sample = {12{1'b0}};
    integer pi;
    always @(posedge aclk) begin
        #0.05;
        pretty_sample <= outsample[0];
        pretty_insample <= samples[0];
        for (pi=1;pi<8;pi=pi+1) begin
            #(5.0/8);
            pretty_sample <= outsample[pi];
            pretty_insample <= samples[pi];
        end
    end
   

    `DEFINE_WB_IF( wb_ , 7, 32);
    assign wb_cyc_o = wr;
    assign wb_stb_o = wr;
    assign wb_we_o = wr;
    assign wb_sel_o = {4{wr}};
    assign wb_dat_o = data;
    assign wb_adr_o = address;
    assign ack = wb_ack_i;
    
    biquad8_wrapper #(.NBITS(12), .NFRAC(0),
                      .OUTBITS(12),.OUTFRAC(0))
                    u_wrapper(.wb_clk_i(wbclk),
                              .wb_rst_i(1'b0),
                              `CONNECT_WBS_IFM( wb_ , wb_ ),
                              .clk_i( aclk ),
                              .global_update_i( 1'b0 ),
                              .dat_i(sample_arr),
                              .dat_o(outsample_arr));
        
    task do_write;
        input [6:0] in_addr;
        input [31:0] in_data;
        begin
            @(posedge wbclk);
            #1 wr = 1; address = in_addr; data = in_data;
            @(posedge wbclk);
            while (!ack) #1 @(posedge wbclk);
            #1 wr = 0;
        end
    endtask

    integer l;    
    initial begin
        #150;
        do_write( 7'h04, 32'd16384 );
        do_write( 7'h04, 32'd8192 );
        do_write( 7'h00, 32'd1 );
        
        #500;
        for (l=0;l<8;l=l+1) begin
            @(posedge aclk);
            #0.01;
            samples[l] = -1000;
            @(posedge aclk);
            #0.01;
            samples[l] = 0;        
            @(posedge aclk);
            @(posedge aclk);
        end            
    end
    
endmodule
