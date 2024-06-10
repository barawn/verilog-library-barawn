`timescale 1ns / 1ps
// Accumulate the square of a 5-bit input with a symmetric representation.
// Because this is only 5 bits, it ends up being free because we can embed
// the squaring operation inside the logic for the add.
//
// Note! The number of accumulator bits you need is log2(NSAMPLES)+7.
// This is because we don't ACTUALLY compute the accumulated square here:
// the output needs to be shifted up by 1 and NSAMPLES*0.25 needs to be added.
//
// The NSAMPLES*0.25 can be included here as a parameter (RESET_VALUE)
// so long as NSAMPLES*0.25 is 0 for the bottom 8 bits! In other words,
// use a power-of-2 number of samples and make sure it's bigger than 1024
// samples!
//
// Note that it doesn't actually fill the range, the highest value that can
// be added each clock is 120.
//
// Also note that because of the symmetric representation the SMALLEST
// accumulated value we can measure is NSAMPLES*0.125.
//
// If you're wondering about the logic here, which doesn't look like a square:
// it's because of the offset. 
// NBITS MUST BE > 8
// ONLY THE TOP NBITS-8 BITS HAVE A RESET VALUE BOTTOM ONES ARE IGNORED
// ALSO NOTE NOTE: 'WHY DO YOU TAKE IN 4 BITS?' BECAUSE ABS(SIGNED 5 BIT) IS 4 BITS
module square_5bit_accumulator #(parameter NBITS=24,
                                 parameter [NBITS-1:0] RESET_VALUE = {NBITS{1'b0}},
                                 parameter CLKTYPE="NONE")(
        input clk_i,
        input [3:0] in_i,
        input ce_i,
        input rst_i,
        output [NBITS-1:0] accum_o
    );

    // ok, so here's how a normal adder works:
    // Obviously a full adder has sum=(A ^ B ^ Carry)
    //                          carry=((A ^ B) && C) || (A && B)
    // Note that carry can be implemented as a mux:
    //                          carry = (A^B)&&C || !(A^B)&&A
    // or                               (A^B)&&C || !(A^B)&&B
    // This is because !(A^B) is ((!A && !B) || (A && B)) - ANDing with A or B gives A && B automatically.
    //
    // In a normal adder the LUTs are configured as O6 = A ^ B.
    // The sum is computed from A ^ B ^ carry via the carry chain, because the O6 inputs
    // feed S[n] on the chain.
    // The carry is then generated from the muxcy of the previous bit.
    // EITHER OF THE INPUTS CAN BE USED AS THE DI INPUT: these are the two options above.
    //
    // So for us to implement this by *hand*: we need to embed our logic in a LUT6, feed its
    // output to the carry chain, and loop the output's input back to the DI to use the carry chain.
    // There is no need to use a CARRY8, the software's smart enough to merge CARRY4s.
    //
    // Our custom logic only operates on one slice, however, because that's all we need: after that
    // we let the synthesis tools handle it. The other reason we break it up this way is that
    // once we're past 8 bits, it's actually now just an up-counter, which implements *differently*.
    
    // NOTE: there might be a way to combine the bottom 2 bits, but it's unimportant because
    // we're going to use a full slice anyway.
    
    // So first create the "top" register: contains all bits except 8.
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [NBITS-8-1:0] top_register = RESET_VALUE[8 +: (NBITS-8)];
    // carry output from the custom logic. acts as an up-counter input.
    wire top_carry_in;
    
    // here's the accumulator. note we DO NOT HAVE a reset value for the bottom 8!
    // The reason is that it complicates the packing, and we DON'T NEED IT
    // since in our use case we reset to 2^17 * 0.125 = 2^14.
    wire [7:0] bottom_register;
    
    wire [6:0] custom_logic;
    // OK HERE'S THE CUSTOM LOGIC
    // BIT 0: SQUARE LOGIC: I[1] ^ I[0]        = 0x6    0110
    //        OUTPUT LOGIC: I[1] ^ I[0] ^ A[0] = 0x96   1001 0110   
    // DI[0]: A[0]
    LUT3 #(.INIT(8'h96)) u_bit0(.I0(in_i[0]),.I1(in_i[1]),.I2(bottom_register[0]),.O(custom_logic[0]));
    
    // BIT 1: SQUARE LOGIC: I[2] ^ I[1]
    //        OUTPUT LOGIC: I[2] ^ I[1] ^ A[1]
    // DI[1]: A[1]
    LUT3 #(.INIT(8'h96)) u_bit1(.I0(in_i[1]),.I1(in_i[2]),.I2(bottom_register[1]),.O(custom_logic[1]));    

    // BIT 2: SQUARE LOGIC with I[3:0]: 0x17E8
    //        OUTPUT LOGIC with A[2],I[3:0]: 0xE81717E8
    // DI[2]: A[2]
    LUT5 #(.INIT(32'hE81717E8)) u_bit2(.I0(in_i[0]),.I1(in_i[1]),.I2(in_i[2]),.I3(in_i[3]),.I4(bottom_register[2]),.O(custom_logic[2]));
    
    // BIT 3: SQUARE LOGIC WITH I[3:0]: 0xF2B0
    //        OUTPUT LOGIC WITH A[3],I[3:0]: 0x0D4FF2B0
    // DI[3]: A[3]
    LUT5 #(.INIT(32'h0D4FF2B0)) u_bit3(.I0(in_i[0]),.I1(in_i[1]),.I2(in_i[2]),.I3(in_i[3]),.I4(bottom_register[3]),.O(custom_logic[3]));
    
    // BIT 4: SQUARE LOGIC WITH I[3:0]: 0xA4C0
    //        OUTPUT LOGIC WITH A[4],I[3:0]: 0x5B3FA4C0
    // DI[4]: A[4]
    LUT5 #(.INIT(32'h5B3FA4C0)) u_bit4(.I0(in_i[0]),.I1(in_i[1]),.I2(in_i[2]),.I3(in_i[3]),.I4(bottom_register[4]),.O(custom_logic[4]));
    
    // BIT 5: SQUARE LOGIC WITH I[3:0]: 0xC700
    //        OUTPUT LOGIC WITH A[5],I[3:0]: 0x38FFC700
    // DI[5]: A[5]
    LUT5 #(.INIT(32'h38FFC700)) u_bit5(.I0(in_i[0]),.I1(in_i[1]),.I2(in_i[2]),.I3(in_i[3]),.I4(bottom_register[5]),.O(custom_logic[5]));
    
    // BIT 6: SQUARE LOGIC WITH I[3:0]: 0xF800
    //        OUTPUT LOGIC WITH A[6],I[3:0]: 0x07FFF800
    // DI[5]: A[6]
    LUT5 #(.INIT(32'h07FFF800)) u_bit6(.I0(in_i[0]),.I1(in_i[1]),.I2(in_i[2]),.I3(in_i[3]),.I4(bottom_register[6]),.O(custom_logic[6]));

    // these are ALL rst_i's, with no initializer, since the
    // bottom 8 bits of the reset value are ignored!!!!

    // just use 2 carry4's, Xilinx is weird
    wire [3:0] c0_di = bottom_register[3:0];
    wire [3:0] c0_s = custom_logic[3:0];
    wire [3:0] c0_co;
    wire [3:0] c0_o;
    CARRY4 u_c0(.DI(c0_di),.S(c0_s),.CO(c0_co),.O(c0_o),.CYINIT(1'b0));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br0(.D(c0_o[0]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[0]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br1(.D(c0_o[1]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[1]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br2(.D(c0_o[2]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[2]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br3(.D(c0_o[3]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[3]));

        
    wire [3:0] c1_di = bottom_register[7:4];
    wire [3:0] c1_s = {1'b0,custom_logic[6:4]};
    wire [3:0] c1_co;
    wire [3:0] c1_o;
    CARRY4 u_c1(.DI(c1_di),.S(c1_s),.CO(c1_co),.O(c1_o),.CI(c0_co[3]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br4(.D(c1_o[0]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[4]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br5(.D(c1_o[1]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[5]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br6(.D(c1_o[2]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[6]));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    FDRE u_br7(.D(c1_o[3]),.C(clk_i),.CE(ce_i),.R(rst_i),.Q(bottom_register[7]));
    
    always @(posedge clk_i) begin
        if (rst_i) top_register <= RESET_VALUE[8 +: (NBITS-8)];
        else if (ce_i) top_register <= top_register + c1_co[3];
    end        

    assign accum_o = { top_register, bottom_register };    
endmodule
