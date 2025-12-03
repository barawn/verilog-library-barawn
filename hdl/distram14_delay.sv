`timescale 1ns / 1ps
// distributed RAM-based delay, 14 bits max.
// distram-based delays are more power efficient
// than shift registers, because two elements
// (input and output) are switching every clock.
//
// The addresses are switching too, obviously, but if NSAMP
// and the delays are big enough it's still a win.
//
// The DELAY specified here is the intended number of clock delays
// MINUS 1. A delay of 1 can't be done (it would need to cut through
// the RAM).
//
// clk  wraddr  rdaddr  DI      DO_reg
// 0    1       0       DI[0]   X
// 1    2       1       DI[1]   X           DI[0] is captured at rising of 0
//                                          Combinatorially put at input of DO in 1
// 2    3       2       DI[2]   DI[0]       Captured at 2
// 3    4       3       DI[3]   DI[1]
// 4    5       4       DI[4]   DI[2]
// 5    6       5       DI[5]   DI[3]
// 6    7       6       DI[6]   DI[4]
module distram14_delay #(parameter NSAMP=1,
                         parameter NBITS=14,
                         parameter [4:0] DELAY=5)(
        input clk_i,
        input rst_i,
        input [NBITS*NSAMP-1:0] dat_i,
        output [NBITS*NSAMP-1:0] dat_o
    );
    
    reg [4:0] wraddr = DELAY;
    reg [4:0] rdaddr = {5{1'b0}};
    
    reg [NBITS*NSAMP-1:0] dat_reg = {NBITS*NSAMP{1'b0}};
    
    always @(posedge clk_i) begin
        if (rst_i) begin
            wraddr <= DELAY;
            rdaddr <= 5'h00;
        end else begin
            wraddr <= wraddr + 1;
            rdaddr <= rdaddr + 1;
        end
    end
    
    generate
        genvar i;
        for (i=0;i<NSAMP;i=i+1) begin : LP
            wire [13:0] ram_in = dat_i[NBITS*i +: NBITS];
            wire [13:0] ram_out;
            RAM32M16 
                u_mem(.WCLK(clk_i),
                      .WE(1'b1),
                      .ADDRH(wraddr),
                      .ADDRA(rdaddr),
                      .ADDRB(rdaddr),
                      .ADDRC(rdaddr),
                      .ADDRD(rdaddr),
                      .ADDRE(rdaddr),
                      .ADDRF(rdaddr),
                      .ADDRG(rdaddr),
                      .DIA( ram_in[0  +: 2]),
                      .DIB( ram_in[2  +: 2]),
                      .DIC( ram_in[4  +: 2]),
                      .DID( ram_in[6  +: 2]),
                      .DIE( ram_in[8  +: 2]),
                      .DIF( ram_in[10 +: 2]),
                      .DIG( ram_in[12 +: 2]),
                      .DIH( 2'b00 ),
                      .DOA( ram_out[0 +: 2] ),
                      .DOB( ram_out[2 +: 2] ),
                      .DOC( ram_out[4 +: 2] ),
                      .DOD( ram_out[6 +: 2] ),
                      .DOE( ram_out[8 +: 2] ),
                      .DOF( ram_out[10 +: 2] ),
                      .DOG( ram_out[12 +: 2] ));
            always @(posedge clk_i) begin : RR
                dat_reg[NBITS*i +: NBITS] <= ram_out[0 +: NBITS];
            end
        end
    endgenerate
    assign dat_o = dat_reg;
endmodule
