`timescale 1ns / 1ps
module square_5bit_accumulator_tb;

    wire aclk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(aclk));
    
    // THIS IS THE *ABS* OF THE INPUT VALUE
    // REMEMBER WE ARE IN A SYMMETRIC REP
    reg [3:0] square_in = {4{1'b0}};
    
    // NEED TO UPSHIFT BY 1 AND ADD OFFSET
    wire [23:0] accum_out;
    reg ce = 0;
    reg rst = 0;
    
    square_5bit_accumulator u_accum(.clk_i(aclk),
                                    .in_i(square_in),
                                    .ce_i(ce),
                                    .rst_i(rst),
                                    .accum_o(accum_out));
                                    
    task reset;
        begin
            @(posedge aclk);
            @(posedge aclk);
            #1 ce = 0;
            @(posedge aclk);                                    
            #1 rst = 1;
            @(posedge aclk);
            #1 rst = 0;
            @(posedge aclk);
            #1 ce = 1;
        end
    endtask                    
                                    
    initial begin
        #100;
        @(posedge aclk);
        #1 ce = 1;
        @(posedge aclk);
        @(posedge aclk);
        #1 square_in <= 1;
        @(posedge aclk);
        #1 square_in <= 2;
        @(posedge aclk);
        #1 square_in <= 0;
        @(posedge aclk);
        #1 ce = 0;
        @(posedge aclk);
        #1 rst = 1;
        @(posedge aclk);
        #1 rst = 0;
        @(posedge aclk);
        #1 ce = 1;
        @(posedge aclk);
        #1 square_in <= 3;
        @(posedge aclk);
        #1 square_in <= 2;
        @(posedge aclk);
        #1 square_in <= 0;
        
        reset();
        @(posedge aclk);
        #1 square_in <= 4;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 5;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 6;
        @(posedge aclk);
        #1 square_in <= 0;
                
        reset();
        @(posedge aclk);
        #1 square_in <= 7;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 8;
        @(posedge aclk);
        #1 square_in <= 0;


        reset();
        @(posedge aclk);
        #1 square_in <= 9;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 10;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 11;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 12;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 13;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 14;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 15;
        @(posedge aclk);
        #1 square_in <= 0;

        reset();
        @(posedge aclk);
        #1 square_in <= 1;
        @(posedge aclk);
        #1 square_in <= 2;
        @(posedge aclk);
        #1 square_in <= 3;
        @(posedge aclk);
        #1 square_in <= 4;
        @(posedge aclk);
        #1 square_in <= 5;
        @(posedge aclk);
        #1 square_in <= 6;
        @(posedge aclk);
        #1 square_in <= 7;
        @(posedge aclk);
        #1 square_in <= 8;
        @(posedge aclk);
        #1 square_in <= 9;
        @(posedge aclk);
        #1 square_in <= 10;
        @(posedge aclk);
        #1 square_in <= 11;
        @(posedge aclk);
        #1 square_in <= 12;
        @(posedge aclk);
        #1 square_in <= 13;
        @(posedge aclk);
        #1 square_in <= 14;
        @(posedge aclk);
        #1 square_in <= 15;
        @(posedge aclk);
        #1 square_in <= 0;
    end   

endmodule
