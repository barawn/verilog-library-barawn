`timescale 1ns / 1ps
// Implements an 8:2 carry-save compressor for 8-bit inputs.
// This is via a Wallace tree of a 5:3/3:2 compressor feeding into a 5:3 compressor
// and a final 3:2 compressor. Each of these stages is 1 clock right now,
// but might be able to drop the registration requirements if the clock's not
// that fast. Doesn't really change the resource usage.
//
// There's some magic in the low bits to reduce the resource count usage so that
// overall we actually beat the naive estimate (which would be 6*NBITS LUTs)
// by 3 LUTs (which is more impressive than it seems, since if you did it *really*
// naively, it'd be worse).
//
// This is parameterizable down to 5 bits of input. Below that, it doesn't work
// because we use magic to reduce the bottom/top bits, and with 4 bits or less
// those optimizations run into each other (you can do *better* than this for
// 4 bits and less).
//
// The outputs here (SUM/CARRY) should be added in a DSP.
// As with any CSA they should be added (sum + (carry << 1) ).
module fast_csa82_adder #(parameter NBITS=5)(
        input [NBITS-1:0] A,
        input [NBITS-1:0] B,
        input [NBITS-1:0] C,
        input [NBITS-1:0] D,
        input [NBITS-1:0] E,
        input [NBITS-1:0] F,
        input [NBITS-1:0] G,
        input [NBITS-1:0] H,
        input CLK,
        input CE,
        output [(NBITS+2)-1:0] SUM,
        output [(NBITS+2)-1:0] CARRY
    );
    // 5:3 compressor (2LUTs/bit)  -+-5:3 compressor (2LUTs/bit)->3:2 compressor (1LUT/bit)
    // 3:2 compressor (1LUT/bit)    /
    //
    // Let's just look at it from a 3 bit perspective
    // 5:3 compressor output
    // sum =        xyz
    // carry =     xyz0
    // cc =       xyz00
    // 3:2 compressor output
    //              xyz
    //             xyz0
    // Shoving these *again* into a 5:3 compressor, it's now 5 bits
    //            00xyz
    //            0xyz0
    //            xyz00
    //            00xyz
    //            0xyz0
    // Low bit is actually 2->2 output. HOWEVER: let's just look at this. What we're doing is this.
    //             0x    0v
    //             0y -> v0
    // This is POINTLESS: we can just leave the low bits as they are. We just have to remember that
    // the low bit of the carry output is NOT shifted up one: it just is what it is.
    //
    // Next bit is 4->3
    //             w0 = s1
    //            w00 = c2
    //           w000 = d3
    // Next bit is 5->3
    //            x00 = s2
    //           x000 = c3
    //          x0000 = d4
    // Next bit is 3->2
    //           y000 = s3
    //          y0000 = c4
    // Last bit is just a feedthrough.
    //          z0000 = s4
    // So our final bits are actually only 5 bits each, *still*. They don't expand.
    // D is also tiny now, it's only 2 bits.
    //          zyxwv = s
    //          yxw0v = c
    //          xw000 = d
    //
    // Again, remember that the carry output from the second stage has the weirdness
    // that it's LSB is NOT shifted up, but everything else IS.
    
    // There's a target for optimization here: the fact that the NLSB for the
    // middle 5:3 compressor is 4:3 means we're wasting a bit here. We should be
    // able to reorganize things, but I haven't figured out an easy way to do it.
    // Maybe a 6:3 compressor and a register for the low bits? That costs a LUT
    // at stage 1 KINDOF. But stage 2's LSB becomes a 3:2, and the NLSB becomes
    // a 3:2 at stage 2 (the 6:3 compressor's C, the NLSB's 5:3 and 3:2 sum output).
    // The NNLSB is still a 5:3 compress.
    // But that's WAY BETTER. Because now we've organized it at stage 3 such that
    // we have (now counting bits)
    // 2 outputs at B0 (do nothing).
    // 2 outputs at B1 (do nothing).
    // 2 outputs at B2 (do nothing - the 5:3 compressor's S and the 3:2 NLSB's C)
    // 2 outputs at B3 (do nothing - the NNLSB 5:3 compressor's C, the NNNLSB compressor's S)
    // We expand to 3 outputs only at bit *4*. This also means we only have a single
    // zero to output, and instead of B0-B3 being 1LUT/8FFs, it's now just 8FFs.
    // So now our final values look like
    //           zyxwv = s
    //           yxwv0 = c
    //           w0000 = d
    // Note that if you look at the maximum value here it looks *bigger* than what we can allow.
    // But that's just because we're assuming that all of the s/c/d bits are independent, and they're
    // not: the output of a 5:3 compressor can't be 110 or 111, for instance.
    // Now, when we compress this, we'll get
    //          .zyxwv = s
    //         .z0xwv0 = c
    // which we'll fix in the output. Note that we're back in carry-save format.
        
    // This now means
    // stage 1 B0: 3LUT/5FF  stage2 B0: 1LUT/2FF  stage3 B0: 2FF
    // stage 1 B1: 3LUT/5FF  stage2 B1: 1LUT/2FF  stage3 B1: 2FF
    // stage 1 B2: 3LUT/5FF  stage2 B2: 2LUT/3FF  stage3 B2: 2FF
    // stage 1 B3: 3LUT/5FF  stage2 B3: 2LUT/3FF  stage3 B3: 2FF
    // stage 1 B4: 3LUT/5FF  stage2 B4: 2LUT/3FF  stage3 B4: 1LUT/2FF
    // stage 1 B5: 3LUT/5FF  stage2 B5: 2LUT/3FF  stage3 B5: 1LUT/2FF
    // stage 1 B6: 3LUT/5FF  stage2 B6: 2LUT/3FF  stage3 B6: 1LUT/2FF
    // stage 1 B7: 3LUT/5FF  stage2 B7: 2LUT/3FF  stage3 B7: 1LUT/2FF
    //                       stage2 B8: 1LUT/2FF  stage3 B8: 1LUT/2FF
    //                       stage2 B9: 1FF       stage3 B9: 1LUT/2FF
    // vs
    // stage 1 B0: 3LUT/5FF  stage2 B0: 2FF       stage3 B0: 2FF
    // stage 1 B1: 3LUT/5FF  stage2 B1: 2LUT/3FF  stage3 B1: 2FF
    // stage 1 B2: 3LUT/5FF  stage2 B2: 2LUT/3FF  stage3 B2: 2FF
    // stage 1 B3: 3LUT/5FF  stage2 B3: 2LUT/3FF  stage3 B3: 1LUT/2FF
    // stage 1 B4: 3LUT/5FF  stage2 B4: 2LUT/3FF  stage3 B4: 1LUT/2FF
    // stage 1 B5: 3LUT/5FF  stage2 B5: 2LUT/3FF  stage3 B5: 1LUT/2FF
    // stage 1 B6: 3LUT/5FF  stage2 B6: 2LUT/3FF  stage3 B6: 1LUT/2FF
    // stage 1 B7: 3LUT/5FF  stage2 B7: 2LUT/3FF  stage3 B7: 1LUT/2FF
    //                       stage2 B8: 1LUT/2FF  stage3 B8: 1LUT/2FF
    //                       stage2 B9: 1FF       stage3 B9: 1LUT/2FF
    // meaning we save 1LUT/1FF.
    // Counting, the middle stage is now
    // s = 10 bits
    // c = 9 bits
    // d = 6 bits
    // Note that switching from a 5:3+3:2 to a 6:3+2FFs does NOT normally
    // help anything! Normally it's exactly the same with *much* worse routing
    // (6 inputs to 3LUTs, 2 inputs to 2FFs vs 5 inputs to 2LUTs and 3 inputs to 1LUT)
    // It only helps here because it balances the logic load at stage 2.
    // 
    // For a total count of
    // stage 1: 24LUT/40FF vs 24LUT/40FF
    // stage 2: 15LUT/25FF vs 
    // stage 3: 6LUT/20FF
    // or 45LUT/85FF vs 
    //
    //  
    // The LSB/NLSB is now
    // stage1     stage2
    // -------    ----
    // LUT6-FF    LUT6_2-FF
    //     -FF         \-FF
    // LUT6-FF    
    //     -FF    LUT6_2-FF
    // LUT6-FF         \-FF
    // 3LUT/5FF   2LUT/4FF
    //
    // as opposed to
    // LUT6_2-FF  FF
    //      \-FF  FF
    //   LUT6-FF  LUT6_2-FF
    // LUT6_2-FF       \-FF
    //      \-FF    LUT6-FF
    // 3LUT/5FF   2LUT/5FF
    // This then results in
    // xyz  => xyz  ..xyz
    // xyz    xyz0  .xyz0
    // xyz   xyz00  x0000
    // xyz
    // xyz
    //   z
    // xy        z      
    // xyz     xyz
    // xyz    xy00
    //
    
    
    // The way the bit depth expands here is strange.
    // The outputs from the first stage are all NBITS, but
    // of course the c's need to be upshifted by 1,
    // and the d's by 2.
    // So that's technically NBITS+2, but of course since
    // some of those inputs are 0, we treat those differently.
    // The outputs of the *second* stage are NBITS+2, NBITS+1, and NBITS.
    // After going through the final 3:2, they're both NBITS+2,
    // but the carry is of course upshifted by one
    // That covers the full
    // "just shy of NBITS+3" output values, since the biggest value we can
    // output is 8*(2^NBITS - 1), or 2^(NBITS+3) - 8.
    localparam OUTBITS = NBITS + 2;
    // Wires to second stage. We're now sleazing things slightly
    // because the low bits of stage1's 3:2 compressor are just "sums", not "sum/carry".
    wire [NBITS-1:0] s_stage1_53;
    wire [NBITS-1:0] c_stage1_53;
    wire [NBITS-1:0] d_stage1_53;
    wire [NBITS-1:0] s_stage1_32;
    wire [NBITS-1:0] c_stage1_32;

    // wires to 3rd stage
    // These decrease because of our Wallace tree magic.
    wire [OUTBITS-1:0] s_stage2_53; // or NBITS+2
    wire [OUTBITS-2:0] c_stage2_53; // or NBITS+1
    wire [OUTBITS-5:0] d_stage2_53; // or NBITS-2

    // Everything except the LSBs are 5:3 compressors.    
    fast_csa53_adder #(.NBITS(NBITS-1)) u_stage1_53(.A(A[1 +: (NBITS-1)]),
                                                    .B(B[1 +: (NBITS-1)]),
                                                    .C(C[1 +: (NBITS-1)]),
                                                    .D(D[1 +: (NBITS-1)]),
                                                    .E(E[1 +: (NBITS-1)]),
                                              .CLK(CLK),
                                              .CE(CE),
                                              .RST(1'b0),
                                              .SUM(s_stage1_53[1 +: (NBITS-1)]),
                                              .CARRY(c_stage1_53[1 +: (NBITS-1)]),
                                              .CCARRY(d_stage1_53[1 +: (NBITS-1)]));
    // Everything except the LSB are 3:2 compressors.                                                  
    fast_csa32_adder #(.NBITS(NBITS-1)) u_stage1_32(.A(F[1 +: (NBITS-1)]),
                                                 .B(G[1 +: (NBITS-1)]),
                                                 .C(H[1 +: (NBITS-1)]),
                                             .CLK(CLK),.CE(CE),
                                             .RST(1'b0),
                                             .SUM(s_stage1_32[1 +: (NBITS-1)]),
                                             .CARRY(c_stage1_32[1 +: (NBITS-1)]));
    // The LSB is a 6:3 compressor plus 2 FFs.
    fast_csa63_adder #(.NBITS(1)) u_stage1_63(.A(A[0]),
                                              .B(B[0]),
                                              .C(C[0]),
                                              .D(D[0]),
                                              .E(E[0]),
                                              .F(F[0]),
                                              .CLK(CLK),.CE(CE),
                                              .RST(1'b0),
                                              .SUM(s_stage1_53[0]),
                                              .CARRY(c_stage1_53[0]),
                                              .CCARRY(d_stage1_53[0]));
    // again, these two are FAKE, they're both sums.                                             
    FDRE #(.INIT(1'b0)) u_glsb(.D(G[0]),.C(CLK),.CE(CE),.R(1'b0),.Q(s_stage1_32[0]));
    FDRE #(.INIT(1'b0)) u_hlsb(.D(H[0]),.C(CLK),.CE(CE),.R(1'b0),.Q(c_stage1_32[0]));
                                             
    // Second stage.
    // Now the 2 low bits merge in 3:2 compressors. The mix here is a bit odd.
    // bit 0: s_stage1_32[0]/c_stage1_32[0]/s_stage1_53[0]
    // bit 1: s_stage1_32[1]/c_stage1_53[0]/s_stage1_53[1]
    // You can see what we've done here: we've created a 3rd LSB by not compressing the original 2,
    // reducing the load off of the NLSB by 1.
    fast_csa32_adder #(.NBITS(2)) u_stage2_lowbits(.A( s_stage1_32[1:0] ),
                                                  .B( s_stage1_53[1:0] ),
                                                  .C( { c_stage1_53[0], c_stage1_32[0] } ),
                                                  .CLK(CLK),.CE(CE),
                                                  .RST(1'b0),
                                                  .SUM(s_stage2_53[1:0]),
                                                  .CARRY(c_stage2_53[1:0]));
    // Now it's obvious why ccarry has dropped so much.

    // The 5:3 section starts at bit 2, and only goes up to 2 from the end, which
    // means it's NBITS-2 in length.
    // This is because the NMSB only has 3 inputs, and the MSB only has a single input.
    fast_csa53_adder #(.NBITS(NBITS-2)) u_stage2_53(.A(s_stage1_53[2 +: (NBITS-2)]),
                                                    .B(c_stage1_53[2 +: (NBITS-2)]),
                                                    .C(d_stage1_53[0 +: (NBITS-2)]),
                                                    .D(s_stage1_32[2 +: (NBITS-2)]),
                                                    .E(c_stage1_32[1 +: (NBITS-2)]),
                                                    .SUM(   s_stage2_53[ 2 +: (NBITS-2) ]),
                                                    .CARRY( c_stage2_53[ 2 +: (NBITS-2) ]),
                                                    .CCARRY(d_stage2_53[ 0 +: (NBITS-2) ]),
                                                    .CLK(CLK),
                                                    .CE(CE),
                                                    .RST(1'b0));
    // The next-to-MSB is a 3:2 compressor, since it takes
    // c_stage1_53[NBITS-1]
    // c_stage1_32[NBITS-1]                            
    // d_stage1_53[NBITS-2]
    fast_csa32_adder #(.NBITS(1)) u_stage2_NMSB(.A(c_stage1_53[NBITS-1]),
                                               .B(c_stage1_32[NBITS-1]),
                                               .C(d_stage1_53[NBITS-2]),
                                               .SUM( s_stage2_53[OUTBITS-2] ),
                                               .CARRY(c_stage2_53[OUTBITS-2] ),
                                               .CLK(CLK),
                                               .CE(CE),
                                               .RST(1'b0));
    // And the MSB is just a FF, since it only has d_stage1_53[NBITS-1].                                               
    FDRE #(.INIT(1'b0)) u_smsb(.D(d_stage1_53[NBITS-1]),.C(CLK),.CE(CE),.R(1'b0),.Q(s_stage2_53[OUTBITS-1]));

    // Again, our final stage now looks like:
    //          zyxwv = s
    //          yxwv0 = c
    //          x0000 = d
    // Remember the weirdness that came from the first-stage 6:3.
    // 
    // We want to compress that 3:2, which works for the fourth bit and up.    
    // But the bottom 3 bits map to
    //          yxwv
    //          xwv0
    //          0000
    // Now just add.
    //          yxwv
    //          xwv0
    // That's STILL just two outputs. So screw it. Just capture them.
    // Our final outputs then look like
    //          syxwv
    //         c0xwv0
    // Which is, of course, wonky looking, but it's fine. (There was always going to be extra 0s in the output, just depends on where).
    // Note where we begin each: the first 3:2 is at bit 4, and it takes s[4], c[3], and d[0].
    fast_csa32_adder #(.NBITS(OUTBITS-4)) u_stage3_32(.A(s_stage2_53[4 +: (OUTBITS-4)]),
                                                     .B(c_stage2_53[3 +: (OUTBITS-4)]),
                                                     .C(d_stage2_53[0 +: (OUTBITS-4)]),
                                                     .SUM( SUM[4 +: (OUTBITS-4)] ),
                                                     .CARRY( CARRY[4 +: (OUTBITS-4)] ),
                                                     .CLK(CLK),
                                                     .CE(CE),
                                                     .RST(1'b0));
    // Now the bottom bits. Just grab those.
    FDRE #(.INIT(1'b0)) u_stage3_sb0(.D(s_stage2_53[0]),.C(CLK),.CE(CE),.R(1'b0),.Q(SUM[0]));
    FDRE #(.INIT(1'b0)) u_stage3_cb0(.D(c_stage2_53[0]),.C(CLK),.CE(CE),.R(1'b0),.Q(CARRY[0]));

    FDRE #(.INIT(1'b0)) u_stage3_sb1(.D(s_stage2_53[1]),.C(CLK),.CE(CE),.R(1'b0),.Q(SUM[1]));    
    FDRE #(.INIT(1'b0)) u_stage3_cb1(.D(c_stage2_53[1]),.C(CLK),.CE(CE),.R(1'b0),.Q(CARRY[1]));    

    FDRE #(.INIT(1'b0)) u_stage3_sb2(.D(s_stage2_53[2]),.C(CLK),.CE(CE),.R(1'b0),.Q(SUM[2]));    
    FDRE #(.INIT(1'b0)) u_stage3_cb2(.D(c_stage2_53[2]),.C(CLK),.CE(CE),.R(1'b0),.Q(CARRY[2]));    

    FDRE #(.INIT(1'b0)) u_stage3_sb3(.D(s_stage2_53[2]),.C(CLK),.CE(CE),.R(1'b0),.Q(SUM[3]));        
    // and this is the zero that results from the lack of merging.
    assign CARRY[3] = 1'b0;

    // And that's it.
                                                                                              
endmodule
