`timescale 1ns / 1ps
module signed_8b_square_tb;

    wire clk;
    tb_rclk #(.PERIOD(10.0)) u_clk(.clk(clk));
    
    reg signed [7:0] inval = {8{1'b0}};
    wire [14:0] outval;
    reg [14:0] outval_check = {15{1'b0}};
    signed_8b_square uut(.clk_i(clk),.in_i(inval),.out_o(outval));
    
    reg [14:0] outval_xor = {15{1'b0}};
    
    integer i;
    initial begin
        #100;
        for (i=0;i<256;i=i+1) begin
            @(posedge clk);
            #1 inval = i-128;
        end                
    end

    always @(posedge clk) begin
        outval_check <= inval*inval;
        outval_xor <= outval^outval_check;
    end            

endmodule
