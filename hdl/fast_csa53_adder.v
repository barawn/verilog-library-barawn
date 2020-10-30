`timescale 1ns / 1ps
// This implements a 2-LUT 5:3 compressor.
// To convert to a number, add sum + (carry<<1) + (ccarry << 2).
module fast_csa53_adder #(parameter NBITS=8,
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
        output [NBITS-1:0] SUM,
        output [NBITS-1:0] CARRY,
        output [NBITS-1:0] CCARRY
    );
    // 5:3 compressor.
    // The LUT6_2 determines the sum (S) and carry (C), the LUT5 handles the carrycarry (D).
    // Truth tables:
    // 4 3 2 1 0    S C D
    // 0 0 0 0 0    0 0 0 0110 1000 0000
    // 0 0 0 0 1    1 0 0
    // 0 0 0 1 0    1 0 0
    // 0 0 0 1 1    0 1 0
    // 0 0 1 0 0    1 0 0 1001 1110 0000
    // 0 0 1 0 1    0 1 0
    // 0 0 1 1 0    0 1 0
    // 0 0 1 1 1    1 1 0
    // 0 1 0 0 0    1 0 0 1001 1110 0000
    // 0 1 0 0 1    0 1 0
    // 0 1 0 1 0    0 1 0
    // 0 1 0 1 1    1 1 0
    // 0 1 1 0 0    0 1 0 0110 0111 1000
    // 0 1 1 0 1    1 1 0
    // 0 1 1 1 0    1 1 0
    // 0 1 1 1 1    0 0 1
    // 1 0 0 0 0    1 0 0 1001 1110 0000
    // 1 0 0 0 1    0 1 0
    // 1 0 0 1 0    0 1 0
    // 1 0 0 1 1    1 1 0
    // 1 0 1 0 0    0 1 0 0110 0111 0000
    // 1 0 1 0 1    1 1 0
    // 1 0 1 1 0    1 1 0
    // 1 0 1 1 1    0 0 1
    // 1 1 0 0 0    0 1 0 0110 0111 1000
    // 1 1 0 0 1    1 1 0
    // 1 1 0 1 0    1 1 0
    // 1 1 0 1 1    0 0 1
    // 1 1 1 0 0    1 1 0 1001 0001 1110
    // 1 1 1 0 1    0 0 1
    // 1 1 1 1 0    0 0 1
    // 1 1 1 1 1    1 0 1
    // So sum INIT is 32'h96696996
    // carry INIT is  32'h177E7EE8
    // cc INIT is     32'hE8008000
    localparam [31:0] S_53_INIT = 32'h96696996;
    localparam [31:0] C_53_INIT = 32'h177E7EE8;
    localparam [31:0] D_53_INIT = 32'hE8008000;
    // outputs to flops
    wire [NBITS-1:0] s_to_ff;
    wire [NBITS-1:0] c_to_ff;
    wire [NBITS-1:0] d_to_ff;
    generate
        genvar i;
        for (i=0;i<NBITS;i=i+1) begin : BL
            LUT6_2 #(.INIT({C_53_INIT,S_53_INIT}))
                 u_cs_lut(.I5(1'b1),.I4(E[i]),.I3(D[i]),
                          .I2(C[i]),.I1(B[i]),.I0(A[i]),
                          .O5(s_to_ff[i]),
                          .O6(c_to_ff[i]));
            LUT5 #(.INIT(D_53_INIT))
                u_d_lut(.I4(E[i]),.I3(D[i]),.I2(C[i]),
                         .I1(B[i]),.I0(A[i]),
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
