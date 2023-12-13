`timescale 1ns / 1ps
// Optimized seven-bit square module.
// See "Combined unsigned and two's complement squarers" with 7-bit optimized
// matrix. This module further optimizes things into a ternary adder structure
// with as many of the partial products embedded in the add logic as possible.
//
// This module *actually* computes only (n^2/4) if even and (n^2-1)/4 if odd.
// If you want to test it, register in_i[0] and output (out_o << 1, 1'b0, in_reg[0]).
//
// This is done to allow optimization of any remaining logic.
//
// VERIFIED WITH ALL POSSIBLE SEVEN BIT INPUTS
module seven_bit_square(
        input clk_i,
        input [6:0] in_i,
        output [11:0] out_o
    );
    
    // Auxiliary LUTs.
    
    // o2/o3 take in in_i[2], in_i[1], in_i[0] and generate the low 2 bits.
    // o2 = a1*!a0              = 0x44444444
    // o3 = !a2a1a0 + a2!a1a0   = 0x28282828
    wire out_b2;
    wire out_b3;
    LUT6_2 #(.INIT(64'h2828282844444444)) u_o2o3(.I2(in_i[2]),.I1(in_i[1]),.I0(in_i[0]),
                                                 .I5(1'b1),
                                                 .O5(out_b2),.O6(out_b3));
    FD u_b2(.D(out_b2),.Q(out_o[0]),.C(clk_i));    
    FD u_b3(.D(out_b3),.Q(out_o[1]),.C(clk_i));

    // P6a/P6b takes in a5/a0/a3/a2
    // P6a = a3*!a2 = 0x44444444
    // P6b = a5*a0  = 0xF000F000
    wire [1:0] partial_b6;
    LUT6_2 #(.INIT(64'hF000F00044444444)) u_p6(.I3(in_i[5]),.I2(in_i[0]),.I1(in_i[3]),.I0(in_i[2]),
                                               .I5(1'b1),
                                               .O5(partial_b6[0]),
                                               .O6(partial_b6[1]));


    // The next 2 LUTs generate partials for b7-b9 from embedded compresses, and the extra bit needed for b10/b11.
    wire [9:7] partial_compress;
    wire partial_b2b1;

    // This LUT generates both the compressed b7 input and the doubly-compressed
    // b8 input.
    
    // For logic tables, because of the way the online tool presents them, use
    // a = I4
    // b = I3
    // c = I2
    // d = I1
    // e = I0
    // for 5 input lookup tables        
    
    // b7: a=a5, b=a4, c=a3, d=a2, e=a1
    // b7's compress is a3a2 ^ a5a1 ^ a4a2
    //                 = (cd^ae^bd)
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=CD+%5E+AE+%5E+BD    
    // = A66A0CC0
    // Carry-save output is then (cdae + cdbd + aebd)        
    // then the b8 input is a4~a3 ^ a5a2 ^ b7_any2
    //                      (b~c)^(ad)^(cdae + cdbd + aebd)
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=%28b%7Ec%29%5E%28ad%29%5E%28cdae+%2B+cdbd+%2B+aebd%29
    // = 0B4CCF00
    LUT6_2 #(.INIT(64'h0B4CCF00A66A0CC0)) u_pc78(.I4(in_i[5]),.I3(in_i[4]),.I2(in_i[3]),.I1(in_i[2]),.I0(in_i[1]),
                                                 .I5(1'b1),
                                                 .O5(partial_compress[7]),
                                                 .O6(partial_compress[8]));
    // bit9 has the same inputs.
    // we now work with b8 carry-save output:
    // b8_any2 = (b~cad + b~c(cdae+cdbd+aebd) + ad(cdae+bdbd+aebd))
    // (a4~a3 && a5a2) or (a4~a3 && b7_any2) or (a5a2 && b7_any2)
    //
    // as a4a3 ^ a5a3 ^ b8_any2
    //    bc ^ ac ^ (b~cad + b~c(cdae+cdbd+aebd) + ad(cdae+bdbd+aebd))
    //    I3I2 ^ I4I2 ^ b8_any2
    // = CC70F000
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=bc+%5E+ac+%5E+%28b%7Ecad+%2B+b%7Ec%28cdae%2Bcdbd%2Baebd%29+%2B+ad%28cdae%2Bbdbd%2Baebd%29%29
    // and bit9_any2 (A3) is now
    // bcac + bc((b~cad + b~c(cdae+cdbd+aebd) + ad(cdae+bdbd+aebd))) + ac((b~cad + b~c(cdae+cdbd+aebd) + ad(cdae+bdbd+aebd)))
    // At this point things compress significantly:
    // A3 = acde + abc = a5a3a2a1 + a5a4a3
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=bcac+%2B+bc%28%28b%7Ecad+%2B+b%7Ec%28cdae%2Bcdbd%2Baebd%29+%2B+ad%28cdae%2Bbdbd%2Baebd%29%29%29+%2B+ac%28%28b%7Ecad+%2B+b%7Ec%28cdae%2Bcdbd%2Baebd%29+%2B+ad%28cdae%2Bbdbd%2Baebd%29%29%29
    // and b10/b11 can generate A3 internally if they have a2a1, which is just
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=AB
    //  = 0x88888888
    LUT6_2 #(.INIT(64'h88888888CC70F000)) u_pc910(.I4(in_i[5]),.I3(in_i[4]),.I2(in_i[3]),.I1(in_i[2]),.I0(in_i[1]),
                                                 .I5(1'b1),
                                                 .O5(partial_compress[9]),
                                                 .O6(partial_b2b1));

    // TERNARY ADDER ARCHITECTURE
    // This is an 8-bit ternary adder. No need for top any2.
    wire [6:0] ternary_any2;
    wire [7:0] ternary_sum;
    // B4 needs a3/a2/a1/a0: sum = a2*!a1 ^ a3*a0 ^ a2*a1*a0
    //                      any2 = a3a2!a1a0 + a3a2a1a0 + a2!a1a2a1a0
    //                           = a3a2a0
    // a3=a, a2=b, a1=c, a0=d
    // any2 = b~cad + b~cbcd + adbcd = abd
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=b%7Ecad+%2B+b%7Ecbcd+%2B+adbcd
    //    = 0xA000A000
    //    - SUM:    0x1AB01AB0
    //    - ANY2:   0xA000A000
    LUT6_2 #(.INIT(64'h1AB01AB0A000A000)) u_bit4(.I4(1'b0),
                                                 .I3(in_i[3]),.I2(in_i[2]),.I1(in_i[1]),.I0(in_i[0]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[0]),
                                                 .O6(ternary_sum[0]));
    // B5 takes in 5 inputs because it can regenerate ternary_any2[0] anyway.
    //      b5 = (a2a1 + a4a0 + a3a1) + a3a2a0
    //    any2 = a4a2a1a0 + a3a2a1 + a4a3a1a0
    // a4=a, a3=b, a2=c, a1=d, a0=e
    //         = acde + bcd + abde
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=acde+%2B+bcd+%2B+abde
    //         = 0xC880C000
    // - SUM: 0x066AACC0
    // - ANY2:0xC880C000
    LUT6_2 #(.INIT(64'h066AACC0C880C000)) u_bit5(.I4(in_i[4]),
                                                 .I3(in_i[3]),.I2(in_i[2]),.I1(in_i[1]),.I0(in_i[0]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[1]),
                                                 .O6(ternary_sum[1]));                                                 
    // B6 gets two partial products. partial_b6[1:0]
    // I3: partial_b6[1] I2: partial_b6[0] I1: in_i[4] I0: in_i[1]
    //  - SUM:  0x78878778
    //  - ANY2: 0xF880F880
    LUT6_2 #(.INIT(64'h78878778F880F880)) u_bit6(.I4(ternary_any2[1]),
                                                 .I3(partial_b6[1]),
                                                 .I2(partial_b6[0]),
                                                 .I1(in_i[4]),.I0(in_i[1]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[2]),
                                                 .O6(ternary_sum[2]));    
    // and now we're at B7, which uses the partial_compress bits. b7/b8/b9 will all have the
    // same init, just slightly different inputs.
    // Bit 7 I[3] = ternary_any2[2], I[2] = partial_compress[7], I[1]=in_i[6], I[0]=in_i[0]
    //       a                       b                           c             d
    // O6 = a^b^cd
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=a%5Eb%5E%28cd%29
    //    = 0x87788778
    // O5 = bcd
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=%28a%2B%7Ea%29bcd
    //    = 0x80808080
    LUT6_2 #(.INIT(64'h8778877880808080)) u_bit7(.I3(ternary_any2[2]),
                                                 .I2(partial_compress[7]),
                                                 .I1(in_i[6]),
                                                 .I0(in_i[0]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[3]),
                                                 .O6(ternary_sum[3]));
    LUT6_2 #(.INIT(64'h8778877880808080)) u_bit8(.I3(ternary_any2[3]),
                                                 .I2(partial_compress[8]),
                                                 .I1(in_i[6]),
                                                 .I0(in_i[1]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[4]),
                                                 .O6(ternary_sum[4]));
    LUT6_2 #(.INIT(64'h8778877880808080)) u_bit9(.I3(ternary_any2[4]),
                                                 .I2(partial_compress[9]),
                                                 .I1(in_i[6]),
                                                 .I0(in_i[2]),
                                                 .I5(1'b1),
                                                 .O5(ternary_any2[5]),
                                                 .O6(ternary_sum[5]));
    // At bit 10 we only have 3 inputs, so the compression
    // reduces to a single input at bit 10 and a carry at bit 11.
    // We don't need to generate the any2 output here because you
    // can't have any any2 input with only 1 input.
    // So we can use all 6 bits.
    // I5=ternary_any2[5]
    // I4=P21 = a
    // I3=i6  = b
    // I2=i5  = c
    // I1=i4  = d
    // I0=i3  = e
    // A3 = a5a4a3 + a5a3P21 = cde + cea
    // c~d = 1
    // be = 0
    // (cde + cea) = 0
    
    // Sum is (c~d ^ be ^ A3)=(c~d)^(be)^(cde + cea)
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=%28c%7Ed%29%5E%28be%29%5E%28cde+%2B+cea%29
    //      = 0x3A901AB0
    //negate= 0xC56FE54F
    LUT6 #(.INIT(64'hC56FE54F3A901AB0)) u_bit10( .I5(ternary_any2[5]),
                                                 .I4(partial_b2b1),
                                                 .I3(in_i[6]),
                                                 .I2(in_i[5]),
                                                 .I1(in_i[4]),
                                                 .I0(in_i[3]),
                                                 .O(ternary_sum[6]));
    assign ternary_any2[6] = 1'b0;
    
    // Bit 11 has 3 inputs, but we are at the end of the adder chain
    // Same inputs as bit10 except no ternary_any2 input (it's zero)
    // A4 is (bce + c~dea)
    // sum is = cd ^ bd ^ A4 = cd ^ bd ^(bce + c~dea)
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=%28cd%29%5E%28bd%29%5E%28bce+%2B+c%7Edea%29
    //      = 0xACE0ACC0
    // This is actually an unused half-lut!
    LUT5 #(.INIT(32'hACE0ACC0)) u_bit11( .I4(partial_b2b1),
                                         .I3(in_i[6]),
                                         .I2(in_i[5]),
                                         .I1(in_i[4]),
                                         .I0(in_i[3]),
                                         .O(ternary_sum[7]));
    // CARRY CHAIN
    wire [3:0] c0_di;
    wire [3:0] c0_s;
    wire [3:0] c0_co;
    wire [3:0] c0_o;
    CARRY4 u_c0(.DI({ternary_any2[2:0],1'b0}),
                .S(ternary_sum[3:0]),
                .O(c0_o),
                .CO(c0_co),
                .CYINIT(1'b0));    
    wire [3:0] c1_di;
    wire [3:0] c1_s;
    wire [3:0] c1_co;
    wire [3:0] c1_o;
    CARRY4 u_c1(.DI(ternary_any2[6:3]),
                .S(ternary_sum[7:4]),
                .O(c1_o),
                .CO(c1_co),
                .CI(c0_co[3]));
    wire [7:0] fd_in = { c1_o, c0_o };                
    // generates output bits 2-9 (4-11 of the actual square)
    generate
        genvar i;
        for (i=0;i<8;i=i+1) begin : TFD
            FD u_fd(.D(fd_in[i]),.C(clk_i),.Q(out_o[2+i]));
        end
    endgenerate
    
    // BITS 13/12
    // Bits 13/12 take in in_i[6:4] and c1_co[3]
    //                    bcd           a
    // Bit 12: (b~c)^(bcd)^a
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=%28b%7Ec%29%5E%28bcd%29%5Ea
    // = 0x4FB0
    // Bit 13: (ba + bc)
    // https://tma.main.jp/logic/logic.php?lang=en&type=eq&eq=%28bad%2Bba%7Ed%2Bbcd%2Bbc%7Ed%29
    // = 0xF0C0
    wire out_b12;
    wire out_b13;
    LUT6_2 #(.INIT(64'hF0C0F0C04FB04FB0)) u_b12b13(.I3(c1_co[3]),
                                                   .I2(in_i[6]),
                                                   .I1(in_i[5]),
                                                   .I0(in_i[4]),
                                                   .I5(1'b1),
                                                   .O5(out_b12),
                                                   .O6(out_b13));
    FD u_b12(.C(clk_i),.D(out_b12),.Q(out_o[10]));
    FD u_b13(.C(clk_i),.D(out_b13),.Q(out_o[11]));        
endmodule
