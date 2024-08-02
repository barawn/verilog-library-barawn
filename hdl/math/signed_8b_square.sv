`timescale 1ns / 1ps
// Optimized signed 8-bit square.
// See "Combined unsigned and two's complement squarers" with 7-bit combined optimized
// matrix. This module further optimizes things into a ternary adder structure
// with as many of the partial products embedded in the add logic as possible.
//
// The logic here is almost as compact as you can possibly imagine, using 2
// slices of fully-utilized LUTs.
//
// It's *absurdly* smaller than doing
// reg signed [7:0] input_A;
// reg [14:0] output_C;
// always @(posedge clk) output_C <= input_A * input_A;
// which generates about *8 slices* worth of logic.
//
// Checked against all possible 8 bit inputs.
module signed_8b_square(
        input clk_i,
        input [7:0] in_i,        
        output [14:0] out_o
    );

    // unregistered portion
    wire [15:0] logic_out;

    // CONSTANT OUTPUTS
    // no square has a power of 2 since 2 is prime
    assign out_o[1] = 1'b0;
    // odd squares are odd, even squares are even
    assign logic_out[0] = in_i[0];
   
    // COMPRESS INPUTS
    wire [3:0] c_addend;
    wire [3:0] d_addend;    

    // the logic for the c/d addends is big, it's easiest just to work it out
    // the "bonus" is 52(3+~4). It's the carry from one of the compressed bits
    // in the d addend. We work it out here since we calculated the old
    // table first.
    //  6   5   4   3   2       c_addend
    //  0   0   0   0   0   ||  0   0   0   0
    //  0   0   0   0   1   ||  0   0   0   0  
    //  0   0   0   1   0   ||  0   0   0   0
    //  0   0   0   1   1   ||  0   0   0   0
    //
    //  0   0   1   0   0   ||  0   0   0   0
    //  0   0   1   0   1   ||  0   0   0   0
    //  0   0   1   1   0   ||  0   0   0   0
    //  0   0   1   1   1   ||  0   0   0   0 
    //                                          a5 and ~a4, need a2 for BONUS
    //  0   1   0   0   0   ||  0   0   1   0
    //  0   1   0   0   1   ||  0   0   1   1   0010 + BONUS
    //  0   1   0   1   0   ||  0   0   1   1
    //  0   1   0   1   1   ||  0   1   0   0   0011 + BONUS 
    //                                          a5 and a4, need a3a2 for bonus
    //  0   1   1   0   0   ||  0   1   0   0
    //  0   1   1   0   1   ||  0   1   0   0
    //  0   1   1   1   0   ||  0   1   0   1
    //  0   1   1   1   1   ||  0   1   1   0   0101 + BONUS
    //
    //  1   0   0   0   0   || 1    0   0   0
    //  1   0   0   0   1   || 1    0   0   1
    //  1   0   0   1   0   || 1    0   1   0
    //  1   0   0   1   1   || 1    0   1   1
    //
    //  1   0   1   0   0   || 1    1   0   0
    //  1   0   1   0   1   || 1    1   0   1
    //  1   0   1   1   0   || 1    1   1   0
    //  1   0   1   1   1   || 1    1   1   1
    //                                          a5 and ~a4, so a2 does BONUS
    //  1   1   0   0   0   || 0    0   1   0
    //  1   1   0   0   1   || 0    1   0   0   0011+BONUS
    //  1   1   0   1   0   || 0    1   0   1   (0010 + 0011 = 0101)
    //  1   1   0   1   1   || 0    1   1   1   (0011 + 0011 = 0110)+BONUS
    //                                          a5 and a4, need a3a2 for BONUS
    //  1   1   1   0   0   || 1    0   0   0   (0100 + 0100 = 1000)
    //  1   1   1   0   1   || 1    0   0   1   (0101 + 0100 = 1001)
    //  1   1   1   1   0   || 1    0   1   1   (0110 + 0101 = 1011)
    //  1   1   1   1   1   || 1    1   0   1   (0111 + 0101 = (1100) + BONUS
    // Reading from bottom to top, we have
    // c_addend[0] = ECAA4600
    // c_addend[1] = 49CC8700
    // c_addend[2] = 8EF0F800
    // c_addend[3] = F0FF0000
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h49CC8700_ECAA4600)) u_c01(.I5(1'b1),
                                                 .I4(in_i[6]),
                                                 .I3(in_i[5]),
                                                 .I2(in_i[4]),
                                                 .I1(in_i[3]),
                                                 .I0(in_i[2]),
                                                 .O5(c_addend[0]),
                                                 .O6(c_addend[1]));
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'hF0FF0000_8EF0F800)) u_c23(.I5(1'b1),
                                                 .I4(in_i[6]),
                                                 .I3(in_i[5]),
                                                 .I2(in_i[4]),
                                                 .I1(in_i[3]),
                                                 .I0(in_i[2]),
                                                 .O5(c_addend[2]),
                                                 .O6(c_addend[3]));
    // We rework the d_addend entirely since it changed a bunch.
    //  0   a5a2^(~(a4~a3)) a5a1    a3~a2
    // a4                   a4a2    a4a1
    //                      a3a2    a3a2a1
    // The carry bit gets computed from the and of a4 and not d_addend[3].
    //
    //  5   4   3   2   1   d_addend
    //  0   0   0   0   0   || 0    1   0   0   0100+0000+0000 
    //  0   0   0   0   1   || 0    1   0   0   0100+0000+0000
    //  0   0   0   1   0   || 0    1   0   0   0100+0000+0000
    //  0   0   0   1   1   || 0    1   0   0   0100+0000+0000
    
    //  0   0   1   0   0   || 0    1   0   1   adds a3~a2
    //  0   0   1   0   1   || 0    1   0   1   adds a3~a2
    //  0   0   1   1   0   || 0    1   1   0   adds a3a2
    //  0   0   1   1   1   || 0    1   1   1   adds a3a2 and a3a2a1
    
    //  0   1   0   0   0   || 1    0   0   0   0000+1000+0000
    //  0   1   0   0   1   || 1    0   0   1   adds a4a1
    //  0   1   0   1   0   || 1    0   1   0   adds a4a2
    //  0   1   0   1   1   || 1    0   1   1   adds a4a1 and a4a2
    
    //  0   1   1   0   0   || 1    1   0   1   a4, ~(a4~a3), a3~a2 = 1101
    //  0   1   1   0   1   || 1    1   1   0   adds a4a1 = 1110
    //  0   1   1   1   0   || 0    0   0   0   a4, ~(a4~a3), a4a2, a3a2
    //                                          =(0100+1010+0010) = 1_0000 (carry is a4~d[3] 
    //  0   1   1   1   1   || 0    0   1   0   adds a4a1 and a3a2a1 = 1_0010
    //                                          
    //  1   0   0   0   0   || 0    1   0   0   ~(a4~a3)
    //  1   0   0   0   1   || 0    1   1   0   adds a5a1
    //  1   0   0   1   0   || 0    0   0   0   a5a2^(~(a4~a3)
    //  1   0   0   1   1   || 0    0   1   0   adds a5a1
    
    //  1   0   1   0   0   || 0    1   0   1   ~(a4~a3) and a3~a2
    //  1   0   1   0   1   || 0    1   1   1   adds a5a1
    //  1   0   1   1   0   || 0    0   1   0   a3a2 =0000+0000+0010 (since a5a2^(a4~a3))
    //  1   0   1   1   1   || 0    1   0   1   a3a2, a5a1, a3a2a1 (since a5a2^~(a4~a3), 
    //                                          =0010+0000+0011 = 0101
    //
    //  1   1   0   0   0   || 1    0   0   0   a4 only
    //  1   1   0   0   1   || 1    0   1   1   a4, a5a1, a4a1
    //  1   1   0   1   0   || 1    1   1   0   a4, a5a2, a4a2
    //  1   1   0   1   1   || 0    0   0   1   a4, a5a2, a5a1, a4a1, a4a2
    //                                          0110+1011+0000 = 1_0001
    //
    //  1   1   1   0   0   || 1    1   0   1   a4, ~(a4~a3), a3~a2
    //  1   1   1   0   1   || 0    0   0   0   a4, ~(a4~a3), a3~a2, a5a1, a4a1
    //                                          =(0111+1001+0000)=1_0000 (note d[5]=!d[4] && a[4])
    //  1   1   1   1   0   || 1    1   0   0   a4, ~(a4~a3), a5a2, a4a2, a3a2
    //                                          ~(a4~a3)/a5a2 cancel
    //                                          so a4a2+a4+a3a2 = 1100
    //  1   1   1   1   1   || 0    0   0   0   a4, a4a1, a4a2, a5a1, a3a2, a3a2a1 (since a5a2^(~(a4~a3))
    //                                          0010+1011+0011 = 1_0000
    
    // d_addend[0] = 1AB01AB0
    // d_addend[1] = 066AACC0
    // d_addend[2] = 54B330FF 
    // d_addend[3] = 57003F00
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h066AACC0_1AB01AB0)) u_d01(.I5(1'b1),
                                        .I4(in_i[5]),
                                        .I3(in_i[4]),
                                        .I2(in_i[3]),
                                        .I1(in_i[2]),
                                        .I0(in_i[1]),
                                        .O5(d_addend[0]),
                                        .O6(d_addend[1]));
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h57003F00_54B330FF)) u_d23(.I5(1'b1),
                                                .I4(in_i[5]),
                                                .I3(in_i[4]),
                                                .I2(in_i[3]),
                                                .I1(in_i[2]),
                                                .I0(in_i[1]),
                                                .O5(d_addend[2]),
                                                .O6(d_addend[3]));
    // and we also have our partials
    wire x2;    // in_i[7] and in_i[2]
    wire p4;    // in_i[4] and in_i[0]                                
                                                    
    // ok: we also have carries.
    // there is no carry5       // 1    - bit 5 calculates bit 4
    // there is no carry6       // 2    - this also calculates bit 3
    // there is no carry7;      // 3    - this calculates p40
    wire carry8;                // 4
    wire carry9;                // 5
    wire carry10;               // 6
    // there is no carry11      // 7    - this calculates x2
    wire carry12;               // 8 
    // there is no carry13      // 9    - this is available
    // there is no carry14      // 10   - this calculates bit 2

    // the carry chain is 11 bits, add 4 aux luts above = 15 total.
    // Because of MASSIVE STUPIDITY, you have to put the bottom 4 bits in the TOP
    // carry8 to avoid a TOTALLY NEVER TOLD ABOUT RESTRICTION
    // with UltraScale devices.
    
    // it's conceivable you could do this in 14 (especially with Massive Abuse)
    // but who cares
    wire [11:0] carry_di;
    wire [11:0] carry_s;
    wire [11:0] carry_o;
    wire [11:0] carry_co;    
    
    // bit 5 takes in 4/3/2/1/0 and calculates bit 4 as well
    // bit 4 is a2~a1 + a3a0 + a2a1a0
    // bit 5 is a3a1 + a2a1
    // so:          a3a1    a2~a1
    //              a2a1    a3a0
    //                      a2a1a0
    //
    // 3    2   1   0   ||  b5  b4                      4 set (only b5)
    // 0    0   0   0   ||  0   0                       0
    // 0    0   0   1   ||  0   0                       1
    // 0    0   1   0   ||  0   0                       0
    // 0    0   1   1   ||  0   0                       1
    //
    // 0    1   0   0   ||  0   1   =(01+00+00)=01      0
    // 0    1   0   1   ||  0   1   =(01+00+00)=01      1
    // 0    1   1   0   ||  1   0   =(00+10+00)=10      1
    // 0    1   1   1   ||  1   1   =(00+10+01)=11      0   
    //
    // 1    0   0   0   ||  0   0                       0
    // 1    0   0   1   ||  0   1   =(00+01+00)=01      1
    // 1    0   1   0   ||  1   0   =(10+00+00)=10      1
    // 1    0   1   1   ||  1   1   =(10+01+00)=11      0
    //
    // 1    1   0   0   ||  0   1   =(01+00+00)=01      0
    // 1    1   0   1   ||  1   0   =(01+01+00)=10      0
    // 1    1   1   0   ||  0   0   =(10+10+00)=1_00    0   (note the carry is 321 and integrated in d_addend)
    // 1    1   1   1   ||  1   0   =(10+11+01)=1_10    0   (note the carry is 321 and integrated in d_addend).
    // b4 = 1AB0 (duplicate to 1AB01AB0)
    // b5 = ACC0 (extend to 066AACC0)
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h066AACC0_1AB01AB0)) u_b45(.I5(1'b1),
                                                 .I4(in_i[4]),
                                                 .I3(in_i[3]),
                                                 .I2(in_i[2]),
                                                 .I1(in_i[1]),
                                                 .I0(in_i[0]),
                                                 .O5(logic_out[4]),
                                                 .O6(carry_s[0]));
    // fundamentally b45 is generating 31^320^21 and adding it to 40
    // If we put it into CYINIT and DI it won't work: if we treat it
    // as a carry, we're adding *nothing* and so if 31^320^21 is 0,
    // we don't carry.
    // So don't carry: put a[4] into I4, derive the product,
    // and insert the partial into the DI path as a proper add.
    assign carry_di[0] = p4;

    // bit 6 takes in d0, 5, 2, 1, 0
    // The O6 is just d0^50. The bytes cycle through the bottom 3 bits, so
    // byte 0 = 0, byte 1 = AA
    // byte 2 = FF, and byte 3 = 55
    // = 55FFAA00
    // The O5 is bit 3, which is a2a0^a1a0. It's only 1 byte:
    //  0   0   0   0   0   || 0
    //  0   0   0   0   1   || 0
    //  0   0   0   1   0   || 0
    //  0   0   0   1   1   || 1
    //  0   0   1   0   0   || 0
    //  0   0   1   0   1   || 1
    //  0   0   1   1   0   || 0
    //  0   0   1   1   1   || 0
    // = 28 repeated = 28282828
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h55FFAA00_28282828)) u_b6(.I5(1'b1),
                                                .I4(d_addend[0]),
                                                .I3(in_i[5]),
                                                .I2(in_i[2]),
                                                .I1(in_i[1]),
                                                .I0(in_i[0]),
                                                .O5(logic_out[3]),
                                                .O6(carry_s[1]));
    // the d_addend is the add
    assign carry_di[1] = d_addend[0];
    
    // bit 7 takes in d1, 6, 4, 0
    // O6 is d1^60. Just looking at the bottom byte:
    //  0   0   0   0   || 0
    //  0   0   0   1   || 0
    //  0   0   1   0   || 0
    //  0   0   1   1   || 0
    //  0   1   0   0   || 0
    //  0   1   0   1   || 1
    //  0   1   1   0   || 0
    //  0   1   1   1   || 1
    // =A0, and the XOR flips it to 5F. So 5FA05FA0
    // P40 is just I1&&I0 = 88888888
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h5FA05FA0_88888888)) u_b7(.I5(1'b1),
                                                .I4(1'b0),
                                                .I3(d_addend[1]),
                                                .I2(in_i[6]),
                                                .I1(in_i[4]),
                                                .I0(in_i[0]),
                                                .O5(p4),
                                                .O6(carry_s[2]));
    // the d_addend is the add
    assign carry_di[2] = d_addend[1];
    
    // bit 8 is the last in AUX
    //                                          1   1 0 0 0 = bit *24* : should be ZERO
    // 
    // bit 8 is a ternary add, it takes in d2, 7/6/1/0. note one product is ~(a7a0)
    // also note that d[2] is functionally the *input carry* so ignore it for O5
    // 7 6 1 0              O6  O5      top bytes (with d2)
    // 0 0 0 0 ~(a7a0)      1   0       0   0
    // 0 0 0 1 ~(a7a0)      1   0       0   0
    // 0 0 1 0 ~(a7a0)      1   0       0   0
    // 0 0 1 1 ~(a7a0)      1   0       0   0
    //
    // 0 1 0 0 ~(a7a0)      1   0       0   0
    // 0 1 0 1 ~(a7a0)      1   0       0   0
    // 0 1 1 0 ~(a7a0) a6a1 0   1       1   1
    // 0 1 1 1 ~(a7a0) a6a1 0   1       1   1
    //
    // 1 0 0 0 ~(a7a0)      1   0       0   0
    // 1 0 0 1              0   0       1   0
    // 1 0 1 0 ~(a7a0)      1   0       0   0
    // 1 0 1 1              0   0       1   0
    //
    // 1 1 0 0 ~(a7a0)      1   0       0   0
    // 1 1 0 1              0   0       1   0
    // 1 1 1 0 ~(a7a0) a6a1 0   1       1   1
    // 1 1 1 1 a6a1         1   0       0   0
    // O6 = 6AC0953F
    // O5 = 40C040C0
    (* RLOC = "X0Y0" *)
    LUT6_2 #(.INIT(64'h6AC0953F_40C040C0)) u_b8(.I5(1'b1),
                                                .I4(d_addend[2]),
                                                .I3(in_i[7]),
                                                .I2(in_i[6]),
                                                .I1(in_i[1]),
                                                .I0(in_i[0]),
                                                .O5(carry8),
                                                .O6(carry_s[3]));
    assign carry_di[3] = d_addend[2];
    
    // bit 9 is a real ternary add, it takes in carry8, c0, d3, 7, 1. note one product is ~(a7a1)
    // carry8 is the real addend
    // 
    // first nybble is                          7   0   (b/c/ only NOT set when xx11)
    // next nybble has d3: O6=invert, O5=nyb1   8   7
    // next nybble has c0 set: same             8   7
    // next nybble has c0 AND d3 set            7   F
    // top 2 bytes are inverted again, and O5 doesn't care
    // O5 = F770F770
    // O6 = 87787887
    (* RLOC = "X0Y1" *)
    LUT6_2 #(.INIT(64'h87787887_F770F770)) u_b9(.I5(1'b1),
                                                .I4(carry8),
                                                .I3(c_addend[0]),
                                                .I2(d_addend[3]),
                                                .I1(in_i[7]),
                                                .I0(in_i[1]),
                                                .O5(carry9),
                                                .O6(carry_s[4]));
    // only 1 logic level for the carries, so use them as the addend
    assign carry_di[4] = carry8;
    
    // bit 10 is a real ternary add, it takes in our only partial product calc (holy cow)
    // it takes carry9, X2, c1, d3, 4 (product is ~d3 4)
    // X2 is INVERTED here (we get a7a2)
    //                                         O6      O5
    // 00 = 0
    // 01 = 1
    // 10 = 0
    // 11 = 0 
    // so the first nybble xx01 to not set      D       2 (set when xx01)
    // next nybble sets c1, so O6=~O6           2       F (always set since !x2)
    // next nybble sets x2 and not c1           2       0
    // next nybble has x2 and c1                D       2
    // O5 doesn't care about top,flip O6        2DD2    20F2
    // O6 = 2DD2D22D
    // O5 = 20F220F2
    (* RLOC = "X0Y1" *)
    LUT6_2 #(.INIT(64'h2DD2D22D_20F220F2)) u_b10(.I5(1'b1),
                                                 .I4(carry9),
                                                 .I3(x2),
                                                 .I2(c_addend[1]),
                                                 .I1(d_addend[3]),
                                                 .I0(in_i[4]),
                                                 .O5(carry10),
                                                 .O6(carry_s[5]));
    assign carry_di[5] = carry9;

    // bit 11 takes in carry10, c2, 7, 3, 2 (73 is inverted)
    // it generates X2
    // O6 is carry10^c2^73
    // O5 is 72 so A0A0A0A0
    // O6 is ~(73)^c2^carry10
    // byte 0 is            3F (only x11x is NOT set, so bit 6, 7)
    // byte 1 flips it      C0
    // byte 32 flips again  3FC0
    // O6 is 3FC0C03F
    (* RLOC = "X0Y1" *)
    LUT6_2 #(.INIT(64'h3FC0C03F_A0A0A0A0)) u_b11(.I5(1'b1),
                                                 .I4(carry10),
                                                 .I3(c_addend[2]),
                                                 .I2(in_i[7]),
                                                 .I1(in_i[3]),
                                                 .I0(in_i[2]),
                                                 .O5(x2),
                                                 .O6(carry_s[6]));
    assign carry_di[6] = carry10;
    
    // c3, c2,  7,  4,  3  ~(74), ~(73)c2, c3   O5  O6      upper bytes
    // 0    0   0   0   0 | 1       0       0|  0   1       1   0
    // 0    0   0   0   1 | 1       0       0|  0   1       1   0
    // 0    0   0   1   0 | 1       0       0|  0   1       1   0
    // 0    0   0   1   1 | 1       0       0|  0   1       1   0
    //
    // 0    0   1   0   0 | 1       0       0|  0   1       1   0
    // 0    0   1   0   1 | 1       0       0|  0   1       1   0
    // 0    0   1   1   0 | 0       0       0|  0   0       0   1
    // 0    0   1   1   1 | 0       0       0|  0   0       0   1
    // byte 0: O5 = 00, O6=3F
    // 0    1   0   0   0 | 1       1       0|  1   0       1   1
    // 0    1   0   0   1 | 1       1       0|  1   0       1   1
    // 0    1   0   1   0 | 1       1       0|  1   0       1   1
    // 0    1   0   1   1 | 1       1       0|  1   0       1   1
    //
    // 0    1   1   0   0 | 1       1       0|  1   0       1   1
    // 0    1   1   0   1 | 1       0       0|  0   1       1   0
    // 0    1   1   1   0 | 0       1       0|  0   1       1   0
    // 0    1   1   1   1 | 0       0       0|  0   0       0   1
    // byte 1: O5 = 1F, O6=60
    // so first two bytes are O5=1F00 and O6=603F
    // adding upper bytes: O6 = 9FC0603F
    //                     O5 = 7F3F1F00
    (* RLOC = "X0Y1" *)
    LUT6_2 #(.INIT(64'h9FC0603F_7F3F1F00)) u_b12(.I5(1'b1),
                                                .I4(c_addend[3]),
                                                .I3(c_addend[2]),
                                                .I2(in_i[7]),
                                                .I1(in_i[4]),
                                                .I0(in_i[3]),
                                                .O5(carry12),
                                                .O6(carry_s[7]));
    // no actual addend
    assign carry_di[7] = 1'b0;
    
    // bit 13 takes carry12, 7/6/5, but it's a binary adder. O5 is unused
    // the derived term is (~(75)^(65))
    // the first byte is
    //              ~(75)   65  O6
    // 0    0   0   1       0   1
    // 0    0   1   1       0   1
    // 0    1   0   1       0   1
    // 0    1   1   1       1   0
    // 1    0   0   1       0   1
    // 1    0   1   0       0   0
    // 1    1   0   1       0   1
    // 1    1   1   0       1   1   
    // = D7
    // The invert is then 28
    // so 28D728D7
    (* RLOC = "X0Y1" *)
    LUT4 #(.INIT(16'h28D7)) u_b13(.I3(carry12),
                                  .I2(in_i[7]),
                                  .I1(in_i[6]),
                                  .I0(in_i[5]),
                                  .O(carry_s[8]));
    assign carry_di[8] = carry12;
    
    // bit 14 takes 1/0/7/6/5
    // O5 derives 1~0
    // O6 derives (~(7~6)^(~765))
    // 1~0 is set in nybbles 4/5, so O5=00FF0000
    //  7   6   5       ~(7~6)   (~765)  O6
    //  0   0   0       1       0       1
    //  0   0   1       1       0       1
    //  0   1   0       1       0       1
    //  0   1   1       1       1       0
    //  1   0   0       0       0       0
    //  1   0   1       0       0       0
    //  1   1   0       1       0       1
    //  1   1   1       1       0       1
    // = C7, so C7C7C7C7
    (* RLOC = "X0Y1" *)
    LUT6_2 #(.INIT(64'hC7C7C7C7_00FF0000)) u_b14(.I5(1'b1),
                                                 .I4(in_i[1]),
                                                 .I3(in_i[0]),
                                                 .I2(in_i[7]),
                                                 .I1(in_i[6]),
                                                 .I0(in_i[5]),
                                                 .O5(logic_out[2]),
                                                 .O6(carry_s[9]));
    // no addend
    assign carry_di[9] = 1'b0;    
    
    // And that's it for a signed square.

// just try leaving them unconnected
//    // tie off
//    assign carry_di[11] = 1'b0;
//    // and pin one of the LUT6s randomly
//    assign carry_s[11] = 1'b0;
    

    // bottom carry. sigh. stupidity.
    // in order to do this, we end up needing to
    // pin the lower LUT6_2s.
    // the O5s are all the evens (c_addend[0]/c_addend[2])
    // the O6s are all the odds
    wire [7:0] lower_di = { carry_di[3:0],
                            c_addend[2],
                            c_addend[0],
                            d_addend[2],
                            d_addend[0] };
    wire [7:0] lower_s = { carry_s[3:0],
                           c_addend[3],
                           c_addend[1],
                           d_addend[3],
                           d_addend[1] };
    wire [7:0] lower_co;
    wire [7:0] lower_o;
    assign carry_co[3:0] = lower_co[7:4];
    assign carry_o[3:0] = lower_o[7:4];
    
    (* RLOC = "X0Y0" *)
    CARRY8 #(.CARRY_TYPE("DUAL_CY4"))
           u_carry1(.CI_TOP(1'b0),.CI(1'b0),.DI(lower_di),
                    .S(lower_s),
                    .O(lower_o),
                    .CO(lower_co));
    // upper carry8 
    (* RLOC = "X0Y1" *)
    CARRY8 u_carry0(.CI(carry_co[3]),
                    .DI(carry_di[11:4]),
                    .S(carry_s[11:4]),
                    .O(carry_o[11:4]),
                    .CO(carry_co[11:4]));

    assign logic_out[15:5] = carry_o[10:0];

    // sigh, stupidity
    generate
        genvar i;
        for (i=0;i<15;i=i+1) begin : FDL
            if (i != 1) begin : FF
                // The FFs in the ternary are bits 0/2 plus 9+
                if (i < 3 || i > 8) begin : TERN
                    (* RLOC = "X0Y1" *)
                    FD u_fd(.D(logic_out[i]),.C(clk_i),.Q(out_o[i]));
                end else begin : AUX
                    (* RLOC = "X0Y0" *)
                    FD u_fd(.D(logic_out[i]),.C(clk_i),.Q(out_o[i]));
                end                    
            end
        end
    endgenerate
endmodule
