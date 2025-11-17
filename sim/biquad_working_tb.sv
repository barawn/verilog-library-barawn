`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/21/2025 08:07:27 PM
// Design Name: 
// Module Name: biquad_working_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "interfaces.vh"

module biquad_working_tb;

    wire wb_clk;
    tb_rclk #(.PERIOD(12)) u_wbclk(.clk(wb_clk));
    localparam NSAMP = 4;
    wire clk;
    tb_rclk #(.PERIOD(5)) u_clk(.clk(clk));
    
    reg [NSAMP-1:0][11:0] data = {NSAMP*12{1'b0}};
    
    reg [6:0] adr = {7{1'b0}};
    reg [31:0] dat = {32{1'b0}};
    reg cyc = 0;
    reg we = 0;    
    wire ack;
    wire [31:0] dat_out;
    
    `DEFINE_WB_IF( wb_ , 7, 32 );
    assign wb_adr_o = adr;
    assign wb_dat_o = dat;
    assign dat_out = wb_dat_i;
    assign ack = wb_ack_i;
    assign wb_cyc_o = cyc;
    assign wb_stb_o = cyc;
    assign wb_we_o = we;
    assign wb_sel_o = 4'hF;
    
    reg  [3:0][11:0] rf_in = {4*12{1'b0}};
    wire [3:0][15:0] rf_out;

    reg [3:0][15:0] filt1_out_hold = {4*16{1'b0}};
    always @(posedge clk) begin
        filt1_out_hold <= #0.001 rf_out;
    end        

    reg [15:0] pretty_outsample = {16{1'b0}};
    always @(posedge clk) begin
        #0.002 pretty_outsample <= filt1_out_hold[0];
        #1.25 pretty_outsample  <= filt1_out_hold[1];
        #1.25 pretty_outsample  <= filt1_out_hold[2];
        #1.25 pretty_outsample  <= filt1_out_hold[3];
    end

    reg bypass = 0;

    biquad8_wrapper_v2 #(.NBITS(12),.NFRAC(0),.NSAMP(4))
        uut( .clk_i(clk),
             .wb_clk_i(wb_clk),
             .wb_rst_i(1'b0),
             `CONNECT_WBS_IFM( wb_, wb_ ),
             .bypass_i(bypass),
             .dat_i(rf_in),
             .dat_o(rf_out),
             .rst_i(1'b0),
             .global_update_i(1'b0));
                                          
    // okay, so for the zero fir we need:
    // write 18'h3FDAF (-0.0362251)
    // write 18'h0375A (0.86487368)
    // zero FIR is addr 4
    localparam [17:0] ZFB_2 = 18'h2137;         // 0.51902473 - the middle coeff
    localparam [17:0] ZFA_2 = 18'h35bf;         // 0.83979965 - the outside coeffs

    localparam [17:0] FC1_2 = 18'h3dec9;    // -0.5190247268916138
    localparam [17:0] FC2_2 = 18'h3e5c0;    // -0.4102126310996121
    localparam [17:0] FP_2 = 18'h11d7;      // 0.2787802162181329
    localparam [17:0] FC_2 = 18'h2433;      // 0.5656393389806839

    localparam [17:0] GC1_2 = FC1_2;
    localparam [17:0] GC2_2 = FC2_2;
    localparam [17:0] GC3_2 = 18'h2433;     // 0.5656393389806839
    localparam [17:0] GP_2 = 18'h3ff0e;     // -0.014800587215469474
    localparam [17:0] GC_2 = 18'h189a;      // 0.3844080978194578
    
    localparam [17:0] IZ1_2 = 18'h3DEC9; // -0.51902473
    localparam [17:0] IZ2_2 = 18'h3D482; // -0.6795993
    
    localparam [17:0] C0_2 = 18'h3f70f; // -0.13971793
    localparam [17:0] C1_2 = 18'h98e;   // 0.14931726
    localparam [17:0] C2_2 = 18'h3f982; // -0.10147590704800001
    localparam [17:0] C3_2 = 18'h3f21a; // -0.21721728496749743
    
    localparam [17:0] ZERO_FIR_B = 18'h3FDAF;
    localparam [17:0] ZERO_FIR_A = 18'h0375A;
    
    localparam [17:0] F_CHAIN_1 = 18'h251;      // 0.03619
    localparam [17:0] F_CHAIN_2 = 18'h3D162;    // -0.7284
    localparam [17:0] F_PIPELINE = 18'h2205;    // 0.53155

    localparam [17:0] F_CROSS = 18'h3FC9F;      // -0.05279
    
    localparam [17:0] G_CHAIN_1 = 18'h251;
    localparam [17:0] G_CHAIN_2 = 18'h3D162;
    localparam [17:0] G_CHAIN_3 = 18'h3FC9F;    // -0.0528
    localparam [17:0] G_PIPELINE = 18'h21E5;    // 0.52960

    localparam [17:0] G_CROSS = 18'h277;        // 0.0385

    // C2, C3, C1, C0.    
    localparam [17:0] C0 = 18'h11F4;   // 0.2805
    localparam [17:0] C1 = 18'h3FC6A;  // -0.056
    localparam [17:0] C2 = 18'h29E;    // 0.0409
    localparam [17:0] C3 = 18'h11D3;   // 0.2785    
    
    // these need to be OPPOSITE the coefficients from iirnotch
    // e.g. ZMINUS1 = 2Pcos(t)
    //      ZMINUS2 = -P^2
    localparam [17:0] INCR_ZMINUS1 = 18'h251;    //  +0.036225
    localparam [17:0] INCR_ZMINUS2 = 18'h3D14C;  // -0.72974736
    
    task wb_write;
        input [6:0] wb_addr;
        input [31:0] wb_data;
        begin
            @(posedge wb_clk);
            #0.1 dat = wb_data;
                 cyc = 1;
                 we = 1;
                 adr = wb_addr;
            while (!wb_ack_i) @(posedge clk);
            #0.1 dat = 32'd0;
                 adr = 7'h00;
                 cyc = 0;
                 we = 0;
            @(posedge clk);
        end
    endtask
        
    initial begin
        #100;

        wb_write( 7'h4, ZFB_2 );    // 3
        wb_write( 7'h4, ZFA_2 );
        wb_write( 7'h4, ZFB_2 );    // 2
        wb_write( 7'h4, ZFA_2 );
        wb_write( 7'h4, ZFB_2 );    // 1
        wb_write( 7'h4, ZFA_2 );
        wb_write( 7'h4, ZFB_2 );    // 0
        wb_write( 7'h4, ZFA_2 );

        wb_write( 7'h10, FP_2);
        wb_write( 7'h10, FC1_2);
        wb_write( 7'h10, FC2_2);

        wb_write( 7'h14, GP_2);
        wb_write( 7'h14, GC2_2);
        wb_write( 7'h14, GC3_2);
        wb_write( 7'h14, GC1_2);  

        wb_write( 7'h18, FC_2 );
        wb_write( 7'h1C, GC_2 );

        // C2, C3, C1, C0.    
        wb_write( 7'h08, C2_2 );
        wb_write( 7'h08, C3_2 );
        wb_write( 7'h08, C1_2 );
        wb_write( 7'h08, C0_2 );
        
        wb_write( 7'h0C, IZ1_2);
        wb_write( 7'h0C, IZ2_2);
        wb_write( 7'h0C, IZ1_2);
        wb_write( 7'h0C, IZ2_2);


//        // we need to write
//        // 3: ZERO_FIR_A
//        //    ZERO_FIR_B
//        // 2: ZERO_FIR_B
//        //    ZERO_FIR_A
//        // 1: ZERO_FIR_B
//        //    ZERO_FIR_A
//        // 0: ZERO_FIR_B
//        //    ZERO_FIR_A
//        wb_write( 7'h4, ZERO_FIR_B ); // 3
//        wb_write( 7'h4, ZERO_FIR_A );
//        wb_write( 7'h4, ZERO_FIR_B ); // 2
//        wb_write( 7'h4, ZERO_FIR_A );
//        wb_write( 7'h4, ZERO_FIR_B ); // 1
//        wb_write( 7'h4, ZERO_FIR_A );
//        wb_write( 7'h4, ZERO_FIR_B ); // 0
//        wb_write( 7'h4, ZERO_FIR_A );
//        // F chain is 10. We program in
//        // -> pipeline coeff
//        // -> coeff1    (sample 3)  i=1
//        // -> coeff2    (sample 2)  i=2
//        wb_write( 7'h10, F_PIPELINE);
//        wb_write( 7'h10, F_CHAIN_1);
//        wb_write( 7'h10, F_CHAIN_2);
//        // G chain is 14. We program in
//        // -> pipeline coeff
//        // -> coeff2    (sample 3)  i=2
//        // -> coeff3    (sample 2)  i=3
//        // -> coeff1    (sample 0)  i=1
//        wb_write( 7'h14, G_PIPELINE);
//        wb_write( 7'h14, G_CHAIN_2);
//        wb_write( 7'h14, G_CHAIN_3);
//        wb_write( 7'h14, G_CHAIN_1);  
    
//        wb_write( 7'h18, F_CROSS );
//        wb_write( 7'h1C, G_CROSS );

//        // C2, C3, C1, C0.    
//        wb_write( 7'h08, C2 );
//        wb_write( 7'h08, C3 );
//        wb_write( 7'h08, C1 );
//        wb_write( 7'h08, C0 );

//        // and the incremental goes
//        // z^-22/z^-1 etc. so we have to do it backwards.
//        // (z^-1/z^-2/z^-1/z^-2)
//        wb_write( 7'h0C, INCR_ZMINUS1);
//        wb_write( 7'h0C, INCR_ZMINUS2);
//        wb_write( 7'h0C, INCR_ZMINUS1);
//        wb_write( 7'h0C, INCR_ZMINUS2);

        wb_write( 7'h0, 32'h10001);

        #500;
        @(posedge clk);
        #0.01   rf_in[0] = 12'd1000;
        @(posedge clk);
        #0.01   rf_in[0] = 12'd0;
        #500;
        @(posedge clk);
        #0.01   rf_in[0] = 12'd1000;
        @(posedge clk);
        #0.01 bypass = 1;
        #100;
        @(posedge clk);
        #0.01 bypass = 0;
        @(posedge clk);
        #100;
        @(posedge clk);
        #0.01   rf_in[0] = 12'd0;
        @(posedge clk);
    end
    
endmodule
