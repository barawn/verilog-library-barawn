`timescale 1ns / 1ps
// 6:3 adder. Not that a 6:3 adder is typically a *worse* way to add
// than 3:2s and 5:3s, because the routing is worse (no double-using a LUT6).
// But there are fringe times when it is useful.
module fast_csa63_adder #(parameter NBITS=8,
                          parameter [NBITS-1:0] SUMRESET = {NBITS{1'b0}},
                          parameter [NBITS-1:0] CARRYRESET = {NBITS{1'b0}},
                          parameter [NBITS-1:0] CCARRYRESET = {NBITS{1'b0}})(
        input CLK,
        input CE,
        input RST,
        input [NBITS-1:0] A,
        input [NBITS-1:0] B,
        input [NBITS-1:0] C,
        input [NBITS-1:0] D,
        input [NBITS-1:0] E,
        input [NBITS-1:0] F,
        output [NBITS-1:0] SUM,
        output [NBITS-1:0] CARRY,
        output [NBITS-1:0] CCARRY
    );
    
    // 6:3 compressor.
    // Each LUT6 determines the sum (S), carry (C), and carrycarry (D).
    // Truth tables:
    // 5 4 3 2 1 0    S C D
    // 0 0 0 0 0 0    0 0 0 0110 1000 0000
    // 0 0 0 0 0 1    1 0 0
    // 0 0 0 0 1 0    1 0 0
    // 0 0 0 0 1 1    0 1 0
    // 0 0 0 1 0 0    1 0 0 1001 1110 0000
    // 0 0 0 1 0 1    0 1 0
    // 0 0 0 1 1 0    0 1 0
    // 0 0 0 1 1 1    1 1 0
    // 0 0 1 0 0 0    1 0 0 1001 1110 0000
    // 0 0 1 0 0 1    0 1 0
    // 0 0 1 0 1 0    0 1 0
    // 0 0 1 0 1 1    1 1 0
    // 0 0 1 1 0 0    0 1 0 0110 0111 1000
    // 0 0 1 1 0 1    1 1 0
    // 0 0 1 1 1 0    1 1 0
    // 0 0 1 1 1 1    0 0 1
    // 0 1 0 0 0 0    1 0 0 1001 1110 0000
    // 0 1 0 0 0 1    0 1 0
    // 0 1 0 0 1 0    0 1 0
    // 0 1 0 0 1 1    1 1 0
    // 0 1 0 1 0 0    0 1 0 0110 0111 0000
    // 0 1 0 1 0 1    1 1 0
    // 0 1 0 1 1 0    1 1 0
    // 0 1 0 1 1 1    0 0 1
    // 0 1 1 0 0 0    0 1 0 0110 0111 1000
    // 0 1 1 0 0 1    1 1 0
    // 0 1 1 0 1 0    1 1 0
    // 0 1 1 0 1 1    0 0 1
    // 0 1 1 1 0 0    1 1 0 1001 0001 1110
    // 0 1 1 1 0 1    0 0 1
    // 0 1 1 1 1 0    0 0 1
    // 0 1 1 1 1 1    1 0 1
    // 1 0 0 0 0 0    1 0 0 1001 1110 0000 9 E 0
    // 1 0 0 0 0 1    0 1 0
    // 1 0 0 0 1 0    0 1 0
    // 1 0 0 0 1 1    1 1 0
    // 1 0 0 1 0 0    0 1 0 0110 0111 1000 6 7 8
    // 1 0 0 1 0 1    1 1 0
    // 1 0 0 1 1 0    1 1 0
    // 1 0 0 1 1 1    0 0 1
    // 1 0 1 0 0 0    0 1 0 0110 0111 1000 6 7 8
    // 1 0 1 0 0 1    1 1 0
    // 1 0 1 0 1 0    1 1 0
    // 1 0 1 0 1 1    0 0 1
    // 1 0 1 1 0 0    1 1 0 1001 0001 1110 9 1 E
    // 1 0 1 1 0 1    0 0 1
    // 1 0 1 1 1 0    0 0 1
    // 1 0 1 1 1 1    1 0 1
    // 1 1 0 0 0 0    0 1 0 0110 0111 1000 6 7 8
    // 1 1 0 0 0 1    1 1 0
    // 1 1 0 0 1 0    1 1 0
    // 1 1 0 0 1 1    0 0 1
    // 1 1 0 1 0 0    1 1 0 1001 0001 1110 9 1 E
    // 1 1 0 1 0 1    0 0 1
    // 1 1 0 1 1 0    0 0 1
    // 1 1 0 1 1 1    1 0 1
    // 1 1 1 0 0 0    1 1 0 1001 0001 1110 9 1 E
    // 1 1 1 0 0 1    0 0 1
    // 1 1 1 0 1 0    0 0 1
    // 1 1 1 0 1 1    1 0 1
    // 1 1 1 1 0 0    0 0 1 0110 1000 1111 6 8 F
    // 1 1 1 1 0 1    1 0 1
    // 1 1 1 1 1 0    1 0 1
    // 1 1 1 1 1 1    0 1 1
    localparam [63:0] S63_INIT = 64'h6996966996696996;
    localparam [63:0] C63_INIT = 64'h8117177E177E7EE8;
    localparam [63:0] D63_INIT = 64'hFEE8E880E8008000;
    // outputs to flops
    wire [NBITS-1:0] s_to_ff;
    wire [NBITS-1:0] c_to_ff;
    wire [NBITS-1:0] d_to_ff;
    generate
        genvar i;
        for (i=0;i<NBITS;i=i+1) begin : BL
            LUT6 #(.INIT(S63_INIT))
                 u_s_lut(.I5(F[i]),.I4(E[i]),.I3(D[i]),
                          .I2(C[i]),.I1(B[i]),.I0(A[i]),
                          .O(s_to_ff[i]));
            LUT6 #(.INIT(C63_INIT))
                 u_c_lut(.I5(F[i]),.I4(E[i]),.I3(D[i]),
                          .I2(C[i]),.I1(B[i]),.I0(A[i]),
                          .O(c_to_ff[i]));
            LUT6 #(.INIT(D63_INIT))
                 u_d_lut(.I5(F[i]),.I4(E[i]),.I3(D[i]),
                          .I2(C[i]),.I1(B[i]),.I0(A[i]),
                          .O(d_to_ff[i]));
            if (SUMRESET[i] == 0) begin : SRL
                FDRE #(.INIT(1'b0)) u_sum_ff(.D(s_to_ff[i]),.CE(CE),.R(RST),.C(CLK),.Q(SUM[i]));
            end else begin : SRH
                FDSE #(.INIT(1'b1)) u_sum_ff(.D(s_to_ff[i]),.CE(CE),.S(RST),.C(CLK),.Q(SUM[i]));
            end
            if (CARRYRESET[i] == 0) begin : CRL
                FDRE #(.INIT(1'b0)) u_carry_ff(.D(c_to_ff[i]),.CE(CE),.R(RST),.C(CLK),.Q(CARRY[i]));            
            end else begin : CRH
                FDSE #(.INIT(1'b1)) u_carry_ff(.D(c_to_ff[i]),.CE(CE),.S(RST),.C(CLK),.Q(CARRY[i]));
            end
            if (CCARRYRESET[i] == 0) begin : DRL
                FDRE #(.INIT(1'b0)) u_ccarry_ff(.D(d_to_ff[i]),.CE(CE),.R(RST),.C(CLK),.Q(CCARRY[i]));
            end else begin : DRH
                FDSE #(.INIT(1'b1)) u_ccarry_ff(.D(d_to_ff[i]),.CE(CE),.S(RST),.C(CLK),.Q(CCARRY[i]));
            end
        end
    endgenerate           
endmodule
