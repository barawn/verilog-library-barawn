`timescale 1ns / 1ps
// 2 beam module.
// Each beam input takes in 8x8x5 = 320 total inputs in OFFSET BINARY.
// They are organized as { ch7[39:0], ch6[39:0], ch5[39:0], ch4[39:0], ch3[39:0], ch2[39:0], ch1[39:0], ch0[39:0] }
// with chX = { samp7[4:0], samp6[4:0], samp5[4:0], samp4[4:0], samp3[4:0], samp2[4:0], samp1[4:0], samp0[4:0] }
// so same as the RFDC output.
// You manage the shuffling externally!
//
// Thresholds are a bit goofy. Square inputs are intrinsically 14 bit, and a sum of 16 of them reaches
// 18 bits. We use the DSPs in 2x24 arrangement, but we orient the bits so that the A or B register
// enables can be used to load the thresholds independently.
// The thresholds act as subtracts, but we can't actually subtract, so you need to load in the two's complement.
// Since we compute (sum16 - threshold), the trigger is then equal to NOT the carry.
// Since this, well, sucks, we invert the whole bloody thing using ALUMODE, 
// 
// In the 2x24 arrangement, the 48-bit operand is A:B, with the border at A[6] ({A[5:0],B} is the lower input).
// This means our 18-bit input is B[17:0] and A[23:6], with {A[5:0]} and {A[29:24]} all set to logic 1.
// Yes, it's super-handy that it's exactly 18 bits, although if it would've been more I would've just dropped
// the bits.
//
// This crap is ULTRA-BASIC right now!
module dual_pueo_beam #(parameter NBITS=5, parameter NSAMP=8, parameter NCHAN=8)(
        input clk_i,
        input [NCHAN*NSAMP*NBITS-1:0] beamA_i,
        input [NCHAN*NSAMP*NBITS-1:0] beamB_i,

        input [17:0] thresh_i,
        input [1:0] thresh_ce_i,
        input update_i,        
        
        output [1:0] trigger_o
    );
    
    // vectorize inputs
    wire [NBITS-1:0] beamA_vec[NCHAN-1:0][NSAMP-1:0];
    wire [NBITS-1:0] beamB_vec[NCHAN-1:0][NSAMP-1:0];
    // create the beams.
    wire [NBITS+2:0] beamA[NSAMP-1:0];
    wire [NBITS+2:0] beamB[NSAMP-1:0];
    // absolute value
    wire [NBITS-1:0] beamA_abs[NSAMP-1:0];
    wire [NBITS-1:0] beamB_abs[NSAMP-1:0];
    // square output
    wire [11:0] beamA_sqout[NSAMP-1:0];
    wire [11:0] beamB_sqout[NSAMP-1:0];
    // store the LSBs
    reg [NSAMP-1:0] beamA_lsb = {NSAMP{1'b0}};
    reg [NSAMP-1:0] beamB_lsb = {NSAMP{1'b0}};
    // actual square
    wire [13:0] beamA_sq[NSAMP-1:0];
    wire [13:0] beamB_sq[NSAMP-1:0];    
    
    // 14-bit square through ternary adder
    wire [15:0] ternaryA_out[2:0];
    wire [15:0] ternaryB_out[2:0];

    // and finally out of 3:2 compressor
    wire [15:0] ternaryA_sum;
    wire [15:0] ternaryA_carry;
    wire [15:0] ternaryB_sum;
    wire [15:0] ternaryB_carry;
    
    generate
        genvar ii,jj,kk;
        // sample loop is the outer b/c once we beamform the channels disappear
        for (jj=0;jj<NSAMP;jj=jj+1) begin : SV
            // absolute value. this is actually going from *offset binary* to abs
            reg [NBITS+1:0] beamA_abs = {NBITS+2{1'b0}};
            reg [NBITS+1:0] beamB_abs = {NBITS+2{1'b0}};
            // uh... let's see if this is needed or not
            wire [NBITS+1:0] zero = {NBITS+2{1'b0}};
            for (ii=0;ii<NCHAN;ii=ii+1) begin : CV
                // channels jump by NSAMP*NBITS. also flip to offset binary
                assign beamA_vec[ii][jj] = beamA_i[NCHAN*NSAMP*ii + NSAMP*jj +: NBITS-1];
                assign beamB_vec[ii][jj] = beamB_i[NCHAN*NSAMP*ii + NSAMP*jj +: NBITS-1];
            end
            // beamform A
            fivebit_8way_ternary #(.ADD_CONSTANT(5'd4))
                u_beamA(.clk_i(clk_i),
                        .A(beamA_vec[0][j]),
                        .B(beamA_vec[1][j]),
                        .C(beamA_vec[2][j]),
                        .D(beamA_vec[3][j]),
                        .E(beamA_vec[4][j]),
                        .F(beamA_vec[5][j]),
                        .G(beamA_vec[6][j]),
                        .H(beamA_vec[7][j]),
                        .O(beamA[j]));
            // beamform B
            fivebit_8way_ternary #(.ADD_CONSTANT(5'd4))
                u_beamB(.clk_i(clk_i),
                        .A(beamB_vec[0][j]),
                        .B(beamB_vec[1][j]),
                        .C(beamB_vec[2][j]),
                        .D(beamB_vec[3][j]),
                        .E(beamB_vec[4][j]),
                        .F(beamB_vec[5][j]),
                        .G(beamB_vec[6][j]),
                        .H(beamB_vec[7][j]),
                        .O(beamB[j]));
            ////////////////////////////////////////////////////////////////////
            // TODO: REPLACE THIS SECTION WITH THE signed_8b_square module!!  //
            // ALL THIS WAS BEFORE I FIGURED OUT HOW TO DO THAT               //
            ////////////////////////////////////////////////////////////////////
                
            // offset binary absolute value
            always @(posedge clk_i) begin : ABS               
                if (!beamA[j][NBITS+2]) beamA_abs[j] = zero - beamA[j];
                else beamA_abs[j] <= zero + beamA[j];

                if (!beamB[j][NBITS+2]) beamB_abs[j] = zero - beamB[j];
                else beamB_abs[j] <= zero + beamB[j];
            end
            // and square
            seven_bit_square u_beamA_sq(.clk_i(clk_i),
                                        .in_i(beamA_abs[j]),
                                        .out_o(beamA_sqout[j]));
            seven_bit_square u_beamB_sq(.clk_i(clk_i),
                                        .in_i(beamB_abs[j]),
                                        .out_o(beamB_sqout[j]));
            // LSB store
            always @(posedge clk_i) begin : LSBS
                beamA_lsb[j] <= beamA_abs[j][0];
                beamB_lsb[j] <= beamB_abs[j][0];
            end
            // form actual square
            assign beamA_sq[j] = { beamA_sqout[j], 1'b0, beamA_lsb[j] };
            assign beamB_sq[j] = { beamB_sqout[j], 1'b0, beamB_lsb[j] };
                
            ////////////////////////////////////////////////////////////////////
            //  END TO BE REPLACED WITH THE signed_8b_square module!!         //                
            ////////////////////////////////////////////////////////////////////                
        end        
        for (kk=0;kk<3;kk=kk+1) begin : TERN
            wire [13:0] Ax = beamA_sq[3*kk];
            wire [13:0] Ay = beamA_sq[3*kk+1];
            wire [13:0] Az = (kk==2) ? {14{1'b0}} : beamA_sq[3*kk+2];
            ternary_add_sub_prim #(.input_word_size(14),
                                   .is_signed(1'b0))
                u_ternA(.clk_i(clk_i),
                        .rst_i(1'b0),
                        .x_i(Ax),
                        .y_i(Ay),
                        .z_i(Az),
                        .sum_o(ternaryA_out[kk]));
            wire [13:0] Bx = beamB_sq[3*kk];
            wire [13:0] By = beamB_sq[3*kk+1];
            wire [13:0] Bz = (kk==2) ? {14{1'b0}} : beamB_sq[3*kk+2];
            ternary_add_sub_prim #(.input_word_size(14),
                                   .is_signed(1'b0))
                u_ternB(.clk_i(clk_i),
                        .rst_i(1'b0),
                        .x_i(Bx),
                        .y_i(By),
                        .z_i(Bz),
                        .sum_o(ternaryB_out[kk]));

        end
    endgenerate    
    // run them through 3:2 compressors
    fast_csa32_adder #(.NBITS(16))
        u_beamA_comp(.A(ternaryA_out[0]),
                     .B(ternaryA_out[1]),
                     .C(ternaryA_out[2]),
                     .SUM(ternaryA_sum),
                     .CARRY(ternaryA_carry),
                     .CLK(clk_i),
                     .CE(1'b1),
                     .RST(1'b0));
    fast_csa32_adder #(.NBITS(16))
        u_beamB_comp(.A(ternaryB_out[0]),
                     .B(ternaryB_out[1]),
                     .C(ternaryB_out[2]),
                     .SUM(ternaryB_sum),
                     .CARRY(ternaryB_carry),
                     .CLK(clk_i),
                     .CE(1'b1),
                     .RST(1'b0));
    // and finally through the DSPs
    dual_pueo_beam_dsp u_dsps(.clk_i(clk_i),
                              .beamA_in0_i( {1'b0, ternaryA_sum} ),
                              .beamA_in1_i( {ternaryA_carry, 1'b0} ),
                              .beamB_in0_i( {1'b0, ternaryB_sum} ),
                              .beamB_in1_i( {ternaryB_carry, 1'b0} ),
                              .thresh_i(thresh_i),
                              .thresh_ce_i(thresh_ce_i),
                              .update_i(update_i),
                              .trigger_o(trigger_o));
            
endmodule
