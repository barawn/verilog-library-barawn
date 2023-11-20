`timescale 1ns / 1ps
// multiply a 12-bit signed integer by 23 via ternary add
// annoyingly if you want to, say, replace the entire DSP with these
// you need to redo it a bit to handle bigger widths.
// 12 bits ends up being perfectly matched to use 3 CARRY4s.
//
// Note: resource-wise this is almost exactly the same as a 12-bit adder
module ternary_mult23_12(
        input clk_i,
        input [11:0] in_i,
        output [16:0] out_o
    );

    // full adder logic:
    // sum = a ^ b ^ cin
    // cout = (a&b)||((a^b)&cin)

    // mult by 23 is +16 + 8 - 1
    // two's complement says (in_i<<4)+(in_i<<3)+(~in_i)+1   

    // low 4 bits are custom and unconnected to the ternary add
    // bit0 is always just low input bit since it's ~in_i[0]^1 = in_i[0], carry is ~in_i[0].
    FD #(.INIT(1'b0)) u_bit0(.D(in_i[0]),.C(clk_i),.Q(out_o[0]));
    // bit1/bit2 should be packed into a common LUT, we'll see.    
    // bit1 is just ~in_i[1]^(carry) and carry is just ~in_i[0] so it's ~in_i[1] ^ ~in_i[0], carry is ~in_i[1] && ~in_i[0]
    FD #(.INIT(1'b0)) u_bit1(.D(~in_i[1] ^ ~in_i[0]),.C(clk_i),.Q(out_o[1]));
    // bit2 is just ~in_i[2]^(carry) and carry is ~in_i[1] && ~in_i[0] = ~|in[1:0]
    FD #(.INIT(1'b0)) u_bit2(.D(~in_i[2]^(~|in_i[1:0])),.C(clk_i),.Q(out_o[2]));
    
    // We treat the next 11 bits as a standard ternary adder structure (in the main body). No real reason to
    // do it as a 10-bit because it's the same resource count.
    // The bottom bit inserts bit2's carry as the third bit so the structure stays identical.

    // The ternary adder extends from bit 3 to 15, so we need to extend the input to 16 bits.
    wire [15:0] in_extend = { {4{in_i[11]}}, in_i };
        
    // god I hope this crap works
    // Based on the VHD ternary_adder we can use multiple CARRY4s chained together and
    // they'll be magically recognized as a CARRY8
    
    // DI for the carry4s. We need 3 of them.
    wire [3:0] cc_di[2:0];
    // S for the carry4s.
    wire [3:0] cc_s[2:0];
    // O for the carry4
    wire [3:0] cc_o[2:0];
    // CO for the carry4
    wire [3:0] cc_co[2:0];

    // any2 outputs from each ternary stage
    wire [10:0] ternary_any2;
    // sum outputs from each ternary stage
    wire [10:0] ternary_sum;

    // this needs to be O6 to utilize the carry chain
    wire bit14_sum;
    // this is O5 and generates the sum directly as if we were the top bit
    wire bit15_sum;

    // This is the bottom bit of the ternary adder, but we integrate the "third bit"
    // which is really the carry of the bottom 3, which is just ~|in_i[2:0] = &~in_i[2:0]
    // This is overall a 4-input function so we need a 16-bit LUT value
    // The overall structure works out to be
    // any2 = (~in[3] & in[0]) (set bits 1,3,5,7 = 0000_0000_1010_1010 = 0x00AA)
    //      + (~in[3] & ~in[2] & ~in[1] & ~in[0]) (set bit 0 = 0000_0000_0000_0001 = 0x0001)
    // The third case cannot be set because in[0] & ~in[2] & ~in[1] & ~in[0] is 0 so the final logic is 0x00AA | 0x0001
    // or 0x00AB.
    //
    // The sum is ~in[3]^in[0]^(!in[0] & !in[1] & !in[2]) or
    //      (in[0] & in[3])             bit 9/11/13/15 are set = 1010_1010_0000_0000 = 0xAA00
    //   + (!in[0] & in[1] & !in[3])    bit 2/6 are set =        0000_0000_0100_0100 = 0x0044
    //   + (!in[0] & in[2] & !in[3])    01x0 = 4/6  set =        0000_0000_0101_0000 = 0x0050
    //   + (!in[1] & !in[2] & in[3])    100x = bit 8/9 set =     0000_0011_0000_0000 = 0x0300
    // = 0xAB54
    (* HBLKNM = "MULT23TERN0" *)
    LUT6_2 #(.INIT(64'hAB54AB5400AB00AB)) u_lut3(.I3(in_i[3]),.I2(in_i[2]),.I1(in_i[1]),.I0(in_i[0]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[0]),
                                                 .O6(ternary_sum[0]));
    // Bits 4-13 are 'normal' but because we're inverting bit2 we flip everything byte-by-byte
    // (this is b/c the low nybble is w/bit2 not set, the high nybble is with bit2 set)
    // normal is 6996_6996_e8_e8_e8_e8
    // invert is 9669_9669_8e_8e_8e_8e

    // The remaining bits in the slice are 4/5/6, so we loop them.
    // Note the use of in_extend here because once we get to bit 12 in SL2BODY
    // we are then PAST THE END of in_i originally (k+11 and k=0,1,2)
    generate
        genvar i,j,k;
        for (i=0;i<3;i=i+1) begin : SL0BODY
            // this is where I0's input starts off
            localparam START_BIT=0;
            // we're starting at bit 4, which is bit 1 in the ternary so the prior is just 'i'
            wire prior_any2 = ternary_any2[i];
            wire this_any2;
            wire this_sum;
            // and the current is just i+1
            assign ternary_any2[i+1] = this_any2;
            assign ternary_sum[i+1] = this_sum;
            (* HBLKNM = "MULT23TERN0" *)            
            LUT6_2 #(.INIT(64'h966996698e8e8e8e))  u_lut(.I3(prior_any2),
                                                         // inputs are 4/5/6
                                                         //            1/2/3
                                                         //            0/1/2
                                                         .I2(in_extend[i+START_BIT+4]),
                                                         .I1(in_extend[i+START_BIT+1]),
                                                         .I0(in_extend[i+START_BIT]),
                                                         .I5(1'b1),
                                                         .O5(this_any2),
                                                         .O6(this_sum));
        end
        // next half-slice is 7/8/9/10
        for (j=0;j<4;j=j+1) begin : SL1BODY
            // we start off at 3
            localparam START_BIT=3;
            // we start at bit 7 which is bit 4 in the ternary so the prior is j+3
            wire prior_any2 = ternary_any2[j+3];
            wire this_any2;
            wire this_sum;
            // and the current is just j+4
            assign ternary_any2[j+4] = this_any2;
            assign ternary_sum[j+4] = this_sum;
            (* HBLKNM = "MULT23TERN0" *)            
            LUT6_2 #(.INIT(64'h966996698e8e8e8e))  u_lut(.I3(prior_any2),
                                                         .I2(in_extend[j+START_BIT+4]),
                                                         .I1(in_extend[j+START_BIT+1]),
                                                         .I0(in_extend[j+START_BIT]),
                                                         .I5(1'b1),
                                                         .O5(this_any2),
                                                         .O6(this_sum));            
        end
        // last half-slice is 11/12/13.
        for (k=0;k<3;k=k+1) begin : SL2BODY
            // we start off at 7
            localparam START_BIT=7;
            // we start at bit 11 which is bit 8 in the ternary so the prior is k+7
            wire prior_any2 = ternary_any2[k+7];
            wire this_any2;
            wire this_sum;
            // and current is k+8
            assign ternary_any2[k+8] = this_any2;
            assign ternary_sum[k+8] = this_sum;
            (* HBLKNM = "MULT23TERN1" *)            
            LUT6_2 #(.INIT(64'h966996698e8e8e8e))  u_lut(.I3(prior_any2),
                                                         .I2(in_extend[k+START_BIT+4]),
                                                         .I1(in_extend[k+START_BIT+1]),
                                                         .I0(in_extend[k+START_BIT]),
                                                         .I5(1'b1),
                                                         .O5(this_any2),
                                                         .O6(this_sum));                        
        end
    endgenerate    
    // Bits 14/15 are Now Weird.
    // We do not use the extend anymore because at bit 14/15 we don't have 3 independent bits anymore.
    // If this was a normal ternary structure it would end at bit 14 (I3 to a CARRY4).
    // The ternary structure feeds
    // ternary_sum[ current bit ] into S[ current bit ] (O6 output)
    // ternary_any2[ current bit - 1]   into DI[ current bit ] OR from fabric
    // So that means we want di[3] = ternary_any2[10] and s[3] = bit14_sum.
    // So O6 = bit14_sum and O5 = bit15_sum.
    // We still want to generate the carry chain through bit 14 and in fact we'll loop the carry
    // output back to generate bit 15 through the extra DFF.
    //
    // the 14/15 LUT will take in
    // I0=in[11], I1=in[10], I2=ternary_any2[10], and I3=CO[3]
    // bit14_sum will just be ~in[11] ^ in[11] ^ in[10] ^ ternary_any2[10]
    // a^~a is always 1 (1^0 = 1, 0^1 = 1)
    // 1 ^ in[10] ^ ternary_any2[10] then just becomes
    // !(in[10] ^ ternary_any2[10])
    // or (I1 && I2) + !I1 && !I2
    // view this as
    // x00x bits 0,1,8,9    0000_0011_0000_0011 = 0x0303
    // x11x bits 6,7,14,15  1100_0000_1100_0000 = 0xC0C0
    // or 0xC3C3
    //
    // bit15_sum is just ~in[11] ^ in[11] ^ in[11] ^ bit14_any2 ^ carry_in
    // this is                          1 ^ in[11] ^ bit14_any2 ^ carry_in
    //                                     ~in[11] ^ bit14_any2 ^ carry_in
    // But bit14_any2 is just in[10] sooo
    //                                     ~in[11] ^ in[10] ^ carry_in
    // (a * b * ! d) + (a * ! b * d) + (! a * b * d) + (! a * ! b * ! d)
    // 0x11 = bit 3 and bit 7 = 0000_0000_1000_1000
    // 1x01 = bit 9 and bit 13= 0010_0010_0000_0000
    // 1x10 =bit 10 and bit 14= 0100_0100_0000_0000
    // 0x00 = bit 0 and bit 4 = 0000_0000_0001_0001
    //                          0110_0110_1001_1001 = 6699
    //
    // Bit 16 is trivial. Since NO unsigned values can reach it (23*2047 = B7E9)
    // and ALL negative values have it set....... bit[16] = bit[11]
    // oh and since it's the top bit, it gets run up via sign extension as well
    LUT6_2 #(.INIT(64'hC3C3C3C366996699))
        u_lut14_15(.I0(in_i[11]),
                   .I1(in_i[10]),
                   .I2(ternary_any2[10]),
                   .I3(cc_co[2][3]),
                   .I5(1'b1),
                   .O5(bit15_sum),
                   .O6(bit14_sum));
                                                             
    // Initial CARRY4.
    assign cc_s[0] = ternary_sum[3:0];
    assign cc_di[0] = { ternary_any2[2:0], 1'b0 };    
    (* HBLKNM = "MULT23TERN0" *)            
    CARRY4 u_cc0( .CYINIT(1'b0),
                  .CI(1'b0),
                  .DI(cc_di[0]),
                  .S(cc_s[0]),
                  .CO(cc_co[0]),
                  .O(cc_o[0]));
    // actual outputs are registered O outputs
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit3(.D(cc_o[0][0]),.C(clk_i),.Q(out_o[3]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit4(.D(cc_o[0][1]),.C(clk_i),.Q(out_o[4]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit5(.D(cc_o[0][2]),.C(clk_i),.Q(out_o[5]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit6(.D(cc_o[0][3]),.C(clk_i),.Q(out_o[6]));
    
    // ok now the NEXT carry4
    assign cc_s[1] = ternary_sum[7:4];
    assign cc_di[1] = { ternary_any2[6:3] };
    (* HBLKNM = "MULT23TERN0" *)            
    CARRY4 u_cc1(.CYINIT(1'b0),
                 .CI(cc_co[0][3]),
                 .DI(cc_di[1]),
                 .S(cc_s[1]),
                 .CO(cc_co[1]),
                 .O(cc_o[1]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit7(.D(cc_o[1][0]),.C(clk_i),.Q(out_o[7]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit8(.D(cc_o[1][1]),.C(clk_i),.Q(out_o[8]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit9(.D(cc_o[1][2]),.C(clk_i),.Q(out_o[9]));
    (* HBLKNM = "MULT23TERN0" *)            
    FD #(.INIT(1'b0)) u_bit10(.D(cc_o[1][3]),.C(clk_i),.Q(out_o[10]));

    // Last carry4. The 
    assign cc_s[2] = { bit14_sum , ternary_sum[10:8] };
    assign cc_di[2] = { ternary_any2[10:7] };
    (* HBLKNM = "MULT23TERN1" *)            
    CARRY4 u_cc2(.CYINIT(1'b0),
                 .CI(cc_co[1][3]),
                 .DI(cc_di[2]),
                 .S(cc_s[2]),
                 .CO(cc_co[2]),
                 .O(cc_o[2]));

    (* HBLKNM = "MULT23TERN1" *)            
    FD #(.INIT(1'b0)) u_bit11(.D(cc_o[2][0]),.C(clk_i),.Q(out_o[11]));
    (* HBLKNM = "MULT23TERN1" *)            
    FD #(.INIT(1'b0)) u_bit12(.D(cc_o[2][1]),.C(clk_i),.Q(out_o[12]));
    (* HBLKNM = "MULT23TERN1" *)            
    FD #(.INIT(1'b0)) u_bit13(.D(cc_o[2][2]),.C(clk_i),.Q(out_o[13]));
    (* HBLKNM = "MULT23TERN1" *)
    FD #(.INIT(1'b0)) u_bit14(.D(cc_o[2][3]),.C(clk_i),.Q(out_o[14]));
    (* HBLKNM = "MULT23TERN1" *)
    FD #(.INIT(1'b0)) u_bit15(.D(bit15_sum),.C(clk_i),.Q(out_o[15]));
    // bit 16 is just the input bit 11
    FD #(.INIT(1'b0)) u_bit16(.D(in_i[11]),.C(clk_i),.Q(out_o[16]));
    
                     
endmodule
