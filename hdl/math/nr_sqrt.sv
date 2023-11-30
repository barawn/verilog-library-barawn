`timescale 1ns / 1ps
// Non-restoring square-root implementation:
// key points from "An FPGA implementation of a fixed-point square root operation,"
// K. Piromsopa et al.
// Some fixups (the algorithm in the paper is slightly screwed up)
// and improvements (no need for add/sub, it's just a conditional sign flip).

// NOTE: NBITS MUST BE EVEN AND >= 2 (OF COURSE)
// -- IF YOU WANT MORE PRECISION, JUST MULTIPLY YOUR INPUT BY 4 (lshift by 2) AND EXPAND
//    (since that obviously gets you 2(sqrt(in))
// -- LATENCY IS NBITS/2 CYCLES + 1
// -- MAX NBITS IS 62 I THINK
//
// DON'T ASK ME HOW THIS WORKS, I HAVE NO IDEA, BUT IT DOES
module nr_sqrt #(parameter NBITS=16)(
        input clk_i,
        input calc_i,
        input [NBITS-1:0] in_i,
        output [(NBITS/2)-1:0] out_o,
        output valid_o
    );
    
    // ok, bit counts drive me nuts.
    localparam R_BITS = (NBITS/2)+2;
    localparam Q_BITS = (NBITS/2);
    
    reg running = 0;
    reg [NBITS-1:0] d_reg = {NBITS{1'b0}};
    reg [R_BITS-1:0] r_reg = {R_BITS{1'b0}};
    reg [Q_BITS-1:0] q_reg = {Q_BITS{1'b0}};
    
    // The trick here is that you have (nbits/2) steps.
    // Start with Q=0, R=0.
    // Every step you compute
    // r_reg = input + offset
    // where input  = {r_reg[(NBITS/2)+2-1:2],d_reg[NBITS-1:NBITS-2]}
    // and   offset = {q_reg ^ {(NBITS/2){~r_reg[(NBITS/2)+2-1]},2'b11}
    // and do
    // d_reg = {d_reg[NBITS-3:0],2'b00};
    // that's all she wrote, folks

    // Shift up R and add in the top 2 bits of D.
    wire [R_BITS-1:0] next_input = { r_reg[0 +: R_BITS-2], d_reg[NBITS-2 +: 2] };
    // Add or subtract Q based on the sign of R.
    wire [Q_BITS-1:0] q_or_nq = q_reg ^ {Q_BITS{~r_reg[R_BITS-1]}};

    // Next offset compute. This is our optimization. In the original
    // algorithm it said "if r>=0, you subtract {q,01} and if r<0 you add {q,11}".
    // Except subtracting is just adding the negative, and to flip sign
    // in 2's complement, you invert and add 1. So we go from
    // {q,01} to {~q,10}, and add 1... to get {~q,11}. So we always add, and just
    // conditionally flip bits of Q.
    wire [R_BITS-1:0] next_offset = { q_or_nq, 2'b11 };
    
    // Every clock, compute the next R.
    wire [R_BITS-1:0] next_r = next_input + next_offset;
    
    wire srl_valid;
    SRLC32E u_valid(.D(calc_i),.CE(1'b1),.CLK(clk_i),.A((NBITS/2)-1),.Q(srl_valid));
    reg valid_reg = 0;
    
    always @(posedge clk_i) begin
        if (calc_i) running <= 1;
        else if (srl_valid) running <= 0;

        valid_reg <= srl_valid;
        
        if (calc_i) begin
            d_reg <= in_i;
            r_reg <= {R_BITS{1'b0}};
            q_reg <= {Q_BITS{1'b0}};
        end else if (running) begin
            // update R-reg
            r_reg <= next_r;
            // shift up Q reg and add value if positive.
            q_reg <= {q_reg[0 +: Q_BITS-1], ~next_r[R_BITS-1] };
            // shift up D-reg
            d_reg <= {d_reg[0 +: NBITS-2], 2'b00};            
        end
    end

    assign out_o = q_reg;
    assign valid_o = valid_reg;
endmodule
