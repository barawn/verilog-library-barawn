`timescale 1ns / 1ps
module biquad8_wrapper_tb;
    
    // parameter	     THIS_DESIGN = "ALIGNMENT";
    // parameter	     THIS_DESIGN = "ALIGNMENTZ1";
    // parameter	     THIS_DESIGN = "ALIGNMENTZ121";
    // parameter	     THIS_DESIGN = "ALIGNMENTBQ";
    // parameter	     THIS_DESIGN = "BIQUAD";
    // parameter	     THIS_DESIGN = "IIR";
    parameter	     THIS_DESIGN = "NOINC";

    parameter       SUB_DESIGN = "IIR";

    wire wbclk;
    wire aclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    tb_rclk #(.PERIOD(5.0)) u_aclk(.clk(aclk));

    reg wr = 0;
    reg [6:0] address = {7{1'b0}};
    reg [31:0] data = {32{1'b0}};
    // wire [31:0] data_out;
    wire [47:0] probe0;
    wire [47:0] probe1;
    wire [12*8-1:0] probe3;
    wire [47:0] probe4;
    wire [29:0] probe_inc_low;
    wire [29:0] probe_inc_high;
    wire ack;

    reg [11:0] samples[7:0];
    integer i;
    initial for (i=0;i<8;i=i+1) samples[i] <= 0;
    wire [12*8-1:0] sample_arr =
        { samples[7],
          samples[6],
          samples[5],
          samples[4],
          samples[3],
          samples[2],
          samples[1],
          samples[0] };

    wire [11:0] outsample[7:0];
    wire [12*8-1:0] outsample_arr;

    localparam notch = 650;
    localparam Q = 8;

    generate
        genvar j;
        for (j=0;j<8;j=j+1) begin : DEVEC
            assign outsample[j] = outsample_arr[12*j +: 12];
        end
    endgenerate


    reg [11:0] pretty_insample = {12{1'b0}};
    reg [11:0] pretty_sample = {12{1'b0}};
    integer pi;
    always @(posedge aclk) begin
        #0.05;
        pretty_sample <= outsample[0];
        pretty_insample <= samples[0];
        for (pi=1;pi<8;pi=pi+1) begin
            #(5.0/8);
            pretty_sample <= outsample[pi];
            pretty_insample <= samples[pi];
        end
    end
   

    `DEFINE_WB_IF( wb_ , 7, 32);
    assign wb_cyc_o = wr;
    assign wb_stb_o = wr;
    assign wb_we_o = wr;
    assign wb_sel_o = {4{wr}};
    assign wb_dat_o = data;
    assign wb_adr_o = address;
    assign ack = wb_ack_i;
    
    if (THIS_DESIGN == "NOINC") begin : NOINC
        biquad8_wrapper_no_inc #(.NBITS(12), .NFRAC(0),
                        .OUTBITS(12),.OUTFRAC(0))
                        u_wrapper(.wb_clk_i(wbclk),
                                .wb_rst_i(1'b0),
                                `CONNECT_WBS_IFM( wb_ , wb_ ),
                                .clk_i( aclk ),
                                .global_update_i( 1'b0 ),
                                .dat_i(sample_arr),
                                .dat_o(outsample_arr),
                                .probe0(probe0),
                                .probe1(probe2),
                                // .probe3(probe3),
                                // .probe4(probe4),
                                .probe_inc_low(probe_inc_low),
                                .probe_inc_high(probe_inc_high));
    end else begin : INC
        biquad8_wrapper #(.NBITS(12), .NFRAC(0),
                        .OUTBITS(12),.OUTFRAC(0))
                        u_wrapper(.wb_clk_i(wbclk),
                                .wb_rst_i(1'b0),
                                `CONNECT_WBS_IFM( wb_ , wb_ ),
                                .clk_i( aclk ),
                                .global_update_i( 1'b0 ),
                                .dat_i(sample_arr),
                                .dat_o(outsample_arr),
                                .probe(probe0),
                                .probe2(probe2),
                                .probe3(probe3),
                                .probe4(probe4),
                                .probe_inc_low(probe_inc_low),
                                .probe_inc_high(probe_inc_high));
    end
        
    task do_write;
        input [6:0] in_addr;
        input [31:0] in_data;
        begin
            @(posedge wbclk);
            #1 wr = 1; address = in_addr; data = in_data;
            @(posedge wbclk);
            while (!ack) #1 @(posedge wbclk);
            #1 wr = 0;
        end
    endtask

    integer l;  

    integer   fc, fd, f, fdebug;
    integer   code, dummy, data_from_file;     
    integer coeff_from_file;     
    wire [16:0] data_in;
    
    reg [8*10:1] str;
    initial begin
        #150;

        if (THIS_DESIGN == "ALIGNMENT") begin : ALIGNMENT
            $monitor($sformatf("Beginning Alignment Pulse"));


            $monitor("Prepping IIR");
            do_write( 7'h04, 16384); // B
            do_write( 7'h04, 0); // A


            do_write( 7'h08, 0); // C_2
            do_write( 7'h08, 0); // C_3  // Yes, this is the correct order according to the documentation
            do_write( 7'h08, 0); // C_1
            do_write( 7'h08,0); // C_0

            do_write( 7'h0C, 16384/2); // a_1'  // For incremental computation, unused
            do_write( 7'h0C, 16384/2); // a_2'

            // f FIR
            do_write( 7'h10, 0); // D_FF  
            do_write( 7'h10, 0); // X_6    
            do_write( 7'h10, 0); // X_5   
            do_write( 7'h10, 0);  // X_4   
            do_write( 7'h10, 0);  // X_3   
            do_write( 7'h10, 0);  // X_2   
            do_write( 7'h10, 0);  // X_1 
        
            // g FIR
            do_write( 7'h14, 0);  // E_GG  
            do_write( 7'h14, 0); // X_7 
            do_write( 7'h14, 0);  // X_6
            do_write( 7'h14, 0);  // X_5    
            do_write( 7'h14, 0);  // X_4  
            do_write( 7'h14, 0);  // X_3  
            do_write( 7'h14, 0);  // X_2  
            do_write( 7'h14, 0);  // X_1 
            
            do_write( 7'h18, 0);  // D_FG

            do_write( 7'h1C, 0);  // E_GF

            do_write( 7'h00, 32'd1 );     // Update

            for(int advance=0; advance<10; advance++) begin : ADVANCE_PULSE            

                // Now we do the stimulus here
                #500;
                fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                f = $fopen($sformatf("freqs/outputs/timing_pulse_a1_8192_a2_8192_advance_%1d.dat",advance), "w");
                fdebug = $fopen($sformatf("freqs/outputs/timing_pulse_8192_expanded_advance_%1d.dat",advance), "w");
                // code = $fgets(str, fd);

                for (int i=0; i<advance; i++) begin
                    // Get the next inputs
                    code = $fgets(str, fd);
                    dummy = $sscanf(str, "%d", data_from_file);
                    // samples[i] = 0;
                    // $monitor("Hello World in loop");
                    // $monitor($sformatf("sample is %1d", data_from_file));
                    // $fwrite(f,$sformatf("%1d\n",outsample[i]));
                    #0.01;
                end

                for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                    @(posedge aclk);
                    #0.01;
                    for (int i=0; i<8; i++) begin
                        // Get the next inputs
                        code = $fgets(str, fd);
                        dummy = $sscanf(str, "%d", data_from_file);
                        samples[i] = data_from_file;
                        // $monitor("Hello World in loop");
                        // $monitor($sformatf("sample is %1d", data_from_file));
                        $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        #0.01;
                    end
                    $fwrite(fdebug,$sformatf("%1d\n",probe0));
                    $fwrite(fdebug,$sformatf("%1d\n",probe4));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                end

                $fclose(fd);
                $fclose(fdebug);
                $fclose(f);
            end 
        end else if (THIS_DESIGN == "ALIGNMENTZ1") begin : ALIGNMENTZ1
            $monitor($sformatf("Beginning Alignment Z1 Pulse"));


            $monitor("Prepping Z^-1 through incremental");
            do_write( 7'h04, 16384); // B
            do_write( 7'h04, 0); // A


            do_write( 7'h08, 0); // C_2
            do_write( 7'h08, 0); // C_3  // Yes, this is the correct order according to the documentation
            do_write( 7'h08, 0); // C_1
            do_write( 7'h08,0); // C_0

            do_write( 7'h0C, 0); // a_1'  // For incremental computation, unused
            do_write( 7'h0C, 0); // a_2'

            // f FIR
            do_write( 7'h10, 0); // D_FF  
            do_write( 7'h10, 0); // X_6    
            do_write( 7'h10, 0); // X_5   
            do_write( 7'h10, 0);  // X_4   
            do_write( 7'h10, 0);  // X_3   
            do_write( 7'h10, 0);  // X_2   
            do_write( 7'h10, 0);  // X_1 
        
            // g FIR
            do_write( 7'h14, 0);  // E_GG  
            do_write( 7'h14, 0); // X_7 
            do_write( 7'h14, 0);  // X_6
            do_write( 7'h14, 0);  // X_5    
            do_write( 7'h14, 0);  // X_4  
            do_write( 7'h14, 0);  // X_3  
            do_write( 7'h14, 0);  // X_2  
            do_write( 7'h14, 0);  // X_1 
            
            do_write( 7'h18, 0);  // D_FG

            do_write( 7'h1C, 0);  // E_GF

            do_write( 7'h00, 32'd1 );     // Update

            for(int advance=0; advance<10; advance++) begin : ADVANCE_PULSE            

                // Now we do the stimulus here
                #500;
                fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                f = $fopen($sformatf("freqs/outputs/timing_pulse_a1_0_a2_0_advance_%1d.dat",advance), "w");
                fdebug = $fopen($sformatf("freqs/outputs/timing_pulse_0_expanded_advance_%1d.dat",advance), "w");
                // code = $fgets(str, fd);

                for (int i=0; i<advance; i++) begin
                    // Get the next inputs
                    code = $fgets(str, fd);
                    dummy = $sscanf(str, "%d", data_from_file);
                    // samples[i] = 0;
                    // $monitor("Hello World in loop");
                    // $monitor($sformatf("sample is %1d", data_from_file));
                    // $fwrite(f,$sformatf("%1d\n",outsample[i]));
                    #0.01;
                end

                for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                    @(posedge aclk);
                    #0.01;
                    for (int i=0; i<8; i++) begin
                        // Get the next inputs
                        code = $fgets(str, fd);
                        dummy = $sscanf(str, "%d", data_from_file);
                        samples[i] = data_from_file;
                        // $monitor("Hello World in loop");
                        // $monitor($sformatf("sample is %1d", data_from_file));
                        $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        #0.01;
                    end
                    $fwrite(fdebug,$sformatf("%1d\n",probe0));
                    $fwrite(fdebug,$sformatf("%1d\n",probe4));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                end

                $fclose(fd);
                $fclose(fdebug);
                $fclose(f);
            end 
        end else if (THIS_DESIGN == "ALIGNMENTZ121") begin : ALIGNMENTZ121//CHANGEME
            $monitor($sformatf("Beginning Alignment Z1 Pulse"));


            $monitor("Prepping Z^-1 through incremental");
            do_write( 7'h04, 16384); // B
            do_write( 7'h04, 16384/2); // A


            do_write( 7'h08, 0); // C_2
            do_write( 7'h08, 0); // C_3  // Yes, this is the correct order according to the documentation
            do_write( 7'h08, 0); // C_1
            do_write( 7'h08,0); // C_0

            do_write( 7'h0C, 0); // a_1'  // For incremental computation, unused
            do_write( 7'h0C, 0); // a_2'

            // f FIR
            do_write( 7'h10, 0); // D_FF  
            do_write( 7'h10, 0); // X_6    
            do_write( 7'h10, 0); // X_5   
            do_write( 7'h10, 0);  // X_4   
            do_write( 7'h10, 0);  // X_3   
            do_write( 7'h10, 0);  // X_2   
            do_write( 7'h10, 0);  // X_1 
        
            // g FIR
            do_write( 7'h14, 0);  // E_GG  
            do_write( 7'h14, 0); // X_7 
            do_write( 7'h14, 0);  // X_6
            do_write( 7'h14, 0);  // X_5    
            do_write( 7'h14, 0);  // X_4  
            do_write( 7'h14, 0);  // X_3  
            do_write( 7'h14, 0);  // X_2  
            do_write( 7'h14, 0);  // X_1 
            
            do_write( 7'h18, 0);  // D_FG

            do_write( 7'h1C, 0);  // E_GF

            do_write( 7'h00, 32'd1 );     // Update

            for(int advance=0; advance<10; advance++) begin : ADVANCE_PULSE            

                // Now we do the stimulus here
                #500;
                fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                f = $fopen($sformatf("freqs/outputs/timing_pulse_b_121_a1_0_a2_0_advance_%1d.dat",advance), "w");
                fdebug = $fopen($sformatf("freqs/outputs/timing_pulse_0_expanded_advance_%1d.dat",advance), "w");
                // code = $fgets(str, fd);

                for (int i=0; i<advance; i++) begin
                    // Get the next inputs
                    code = $fgets(str, fd);
                    dummy = $sscanf(str, "%d", data_from_file);
                    // samples[i] = 0;
                    // $monitor("Hello World in loop");
                    // $monitor($sformatf("sample is %1d", data_from_file));
                    // $fwrite(f,$sformatf("%1d\n",outsample[i]));
                    #0.01;
                end

                for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                    @(posedge aclk);
                    #0.01;
                    for (int i=0; i<8; i++) begin
                        // Get the next inputs
                        code = $fgets(str, fd);
                        dummy = $sscanf(str, "%d", data_from_file);
                        samples[i] = data_from_file;
                        // $monitor("Hello World in loop");
                        // $monitor($sformatf("sample is %1d", data_from_file));
                        $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        #0.01;
                    end
                    $fwrite(fdebug,$sformatf("%1d\n",probe0));
                    $fwrite(fdebug,$sformatf("%1d\n",probe4));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                end

                $fclose(fd);
                $fclose(fdebug);
                $fclose(f);
            end 
        end else if (THIS_DESIGN == "ALIGNMENTBQ") begin : ALIGNMENTBQ
            $monitor($sformatf("Beginning Alignment Pulse With BQ"));

            $monitor($sformatf("Notch at %1d MHz, Q at %1d", notch, Q));
            fc = $fopen($sformatf("freqs/coefficients/coeff_file_%1dMHz_%1d.dat", notch, Q),"r");

            if (SUB_DESIGN == "IIR") begin : IIR_SUB
                $monitor("DOING IIR SECTION WITH Z^-1");
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, 16384); // B
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, 0); // A
            end else begin: BQ_SUB
                $monitor("DOING FULL BIQUAD FROM FILE");
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, coeff_from_file); // B
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, coeff_from_file); // A
            end

            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_2
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_1
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_0

            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h0C, coeff_from_file); // a_1'  // For incremental computation
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h0C, coeff_from_file); // a_2'

            // f FIR
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file); // D_FF  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file); // X_6    
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file); // X_5   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_4   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_3   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_2   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_1 
        
            // g FIR
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // E_GG  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file); // X_7 
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_6
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_5    
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_4  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_3  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_2  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_1 
            
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h18, coeff_from_file);  // D_FG

            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h1C, coeff_from_file);  // E_GF

            do_write( 7'h00, 32'd1 );     // Update
                

            for(int advance=0; advance<10; advance++) begin : ADVANCE_PULSE            

                // Now we do the stimulus here
                #500;
                
                if (SUB_DESIGN == "IIR") begin : IIR_SUB_FILE
                    fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                    f = $fopen($sformatf("freqs/outputs/timing_pulse_advance_%1d_IIR.dat",advance), "w");
                    fdebug = $fopen($sformatf("freqs/outputs/timing_BQ_expanded_advance_%1d_IIR.dat",advance), "w");
                    // code = $fgets(str, fd);
                end else begin: BQ_SUB_FILE
                    fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                    f = $fopen($sformatf("freqs/outputs/timing_pulse_advance_%1d_BQZ1.dat",advance), "w");
                    fdebug = $fopen($sformatf("freqs/outputs/timing_BQ_expanded_advance_%1d_BQZ1.dat",advance), "w");
                end

                for (int i=0; i<advance; i++) begin
                    // Get the next inputs
                    code = $fgets(str, fd);
                    dummy = $sscanf(str, "%d", data_from_file);
                    // samples[i] = 0;
                    // $monitor("Hello World in loop");
                    // $monitor($sformatf("sample is %1d", data_from_file));
                    // $fwrite(f,$sformatf("%1d\n",outsample[i]));
                    #0.01;
                end

                for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                    @(posedge aclk);
                    #0.01;
                    for (int i=0; i<8; i++) begin
                        // Get the next inputs
                        code = $fgets(str, fd);
                        dummy = $sscanf(str, "%d", data_from_file);
                        samples[i] = data_from_file;
                        // $monitor("Hello World in loop");
                        // $monitor($sformatf("sample is %1d", data_from_file));
                        $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        #0.01;
                    end
                    $fwrite(fdebug,$sformatf("%1d\n",probe0));
                    $fwrite(fdebug,$sformatf("%1d\n",probe4));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                end

                $fclose(fd);
                $fclose(fdebug);
                $fclose(f);
            end
        end else if (THIS_DESIGN == "NOINC") begin : ALIGNMENTNOINC
            $monitor($sformatf("Beginning non-incremented Alignment Pulse With BQ"));

            $monitor($sformatf("Notch at %1d MHz, Q at %1d", notch, Q));
            fc = $fopen($sformatf("freqs/coefficients_updated/coeff_file_%1dMHz_%1d.dat", notch, Q),"r");

            if (SUB_DESIGN == "IIR") begin : IIR_SUB_NOINC
                $monitor("DOING IIR SECTION WITH Z^-1");
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, 16384); // B
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, 0); // A
            end else begin: BQ_SUB_NOINC
                $monitor("DOING FULL BIQUAD FROM FILE");
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, coeff_from_file); // B
                code = $fgets(str, fc);
                dummy = $sscanf(str, "%d", coeff_from_file);
                do_write( 7'h04, coeff_from_file); // A
            end

            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_2
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_1
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h08, coeff_from_file); // C_0

            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h0C, coeff_from_file); // a_1'  // For incremental computation
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h0C, coeff_from_file); // a_2'

            // f FIR
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file); // D_FF  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file); // X_6    
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file); // X_5   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_4   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_3   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_2   
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h10, coeff_from_file);  // X_1 
        
            // g FIR
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // E_GG  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file); // X_7 
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_6
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_5    
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_4  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_3  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_2  
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h14, coeff_from_file);  // X_1 
            
            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h18, coeff_from_file);  // D_FG

            code = $fgets(str, fc);
            dummy = $sscanf(str, "%d", coeff_from_file);
            do_write( 7'h1C, coeff_from_file);  // E_GF

            do_write( 7'h00, 32'd1 );     // Update
                

            for(int advance=0; advance<10; advance++) begin : ADVANCE_PULSE            

                // Now we do the stimulus here
                #500;
                
                if (SUB_DESIGN == "IIR") begin : IIR_SUB_FILE
                    fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                    f = $fopen($sformatf("freqs/outputs/timing_pulse_advance_%1d_IIR_no_inc_UPDATED.dat",advance), "w");
                    fdebug = $fopen($sformatf("freqs/outputs/timing_BQ_expanded_advance_%1d_IIR_no_inc_UPDATED.dat",advance), "w");
                    // code = $fgets(str, fd);
                end else begin: BQ_SUB_FILE
                    fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                    f = $fopen($sformatf("freqs/outputs/timing_pulse_advance_%1d_BQZ0_no_inc.dat",advance), "w");
                    fdebug = $fopen($sformatf("freqs/outputs/timing_BQ_expanded_advance_%1d_BQZ0_no_inc.dat",advance), "w");
                end

                for (int i=0; i<advance; i++) begin
                    // Get the next inputs
                    code = $fgets(str, fd);
                    dummy = $sscanf(str, "%d", data_from_file);
                    // samples[i] = 0;
                    // $monitor("Hello World in loop");
                    // $monitor($sformatf("sample is %1d", data_from_file));
                    // $fwrite(f,$sformatf("%1d\n",outsample[i]));
                    #0.01;
                end

                for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                    @(posedge aclk);
                    #0.01;
                    for (int i=0; i<8; i++) begin
                        // Get the next inputs
                        code = $fgets(str, fd);
                        dummy = $sscanf(str, "%d", data_from_file);
                        samples[i] = data_from_file;
                        // $monitor("Hello World in loop");
                        // $monitor($sformatf("sample is %1d", data_from_file));
                        $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        #0.01;
                    end
                    $fwrite(fdebug,$sformatf("%1d\n",probe0));
                    $fwrite(fdebug,$sformatf("%1d\n",probe4));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                    $fwrite(fdebug,$sformatf("%1d\n",0));
                end

                $fclose(fd);
                $fclose(fdebug);
                $fclose(f);
            end
        end else begin : FULL_SPECTRUM
            for(int notch=650; notch<1496; notch = notch+10000) begin
                // Zeros
                for(int Q=8; Q<10; Q = Q+2) begin

                    int GAUSS_NOISE_SIZE = 400;
                    // int Q = 8;
                    $monitor($sformatf("Notch at %1d MHz, Q at %1d", notch, Q));
                    fc = $fopen($sformatf("freqs/coefficients/coeff_file_%1dMHz_%1d.dat", notch, Q),"r");

                    if (THIS_DESIGN == "BIQUAD") begin : BIQUAD_TEST
                        $monitor("Prepping Biquad");
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( 7'h04, coeff_from_file); // B
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( 7'h04, coeff_from_file); // A
                    end else begin: IIR_TEST
                        $monitor("Prepping IIR");
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( 7'h04, 16384); // B
                        code = $fgets(str, fc);
                        dummy = $sscanf(str, "%d", coeff_from_file);
                        do_write( 7'h04, 0); // A
                    end

                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h08, coeff_from_file); // C_2
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h08, coeff_from_file); // C_3  // Yes, this is the correct order according to the documentation
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h08, coeff_from_file); // C_1
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h08, coeff_from_file); // C_0

                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h0C, coeff_from_file); // a_1'  // For incremental computation, unused
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h0C, coeff_from_file); // a_2'

                    // f FIR
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file); // D_FF  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file); // X_6    
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file); // X_5   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file);  // X_4   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file);  // X_3   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file);  // X_2   
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h10, coeff_from_file);  // X_1 
                
                    // g FIR
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // E_GG  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file); // X_7 
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // X_6
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // X_5    
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // X_4  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // X_3  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // X_2  
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h14, coeff_from_file);  // X_1 
                    
                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h18, coeff_from_file);  // D_FG

                    code = $fgets(str, fc);
                    dummy = $sscanf(str, "%d", coeff_from_file);
                    do_write( 7'h1C, coeff_from_file);  // E_GF

                    do_write( 7'h00, 32'd1 );     // Update
                    

                    // Now we do the stimulus here
                    #500;
                    fd = $fopen($sformatf("freqs/inputs/pulse_input_height_512_clipped.dat"),"r");
                    if (THIS_DESIGN == "BIQUAD") begin : BIQUAD_PULSE_OUT
                        f = $fopen($sformatf("freqs/outputs/pulse_output_height_512_incremental_notch_%1dMHz_%1dQ.dat", notch, Q), "w");
                        fdebug = $fopen($sformatf("freqs/outputs/pulse_output_height_512_incremental_notch_%1dMHz_%1dQ_expanded.dat", notch, Q), "w");
                    end else begin: IIR_PULSE_OUT
                        f = $fopen($sformatf("freqs/outputs/no_zero_pulse_output_height_512_incremental_notch_%1dMHz_%1dQ.dat", notch, Q), "w");
                        fdebug = $fopen($sformatf("freqs/outputs/no_zero_pulse_output_height_512_incremental_notch_%1dMHz_%1dQ_expanded.dat", notch, Q), "w");
                        // code = $fgets(str, fd);
                    end

                    for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                        @(posedge aclk);
                        #0.01;
                        for (int i=0; i<8; i++) begin
                            // Get the next inputs
                            code = $fgets(str, fd);
                            dummy = $sscanf(str, "%d", data_from_file);
                            samples[i] = data_from_file;
                            // $monitor("Hello World in loop");
                            // $monitor($sformatf("sample is %1d", data_from_file));
                            $fwrite(f,$sformatf("%1d\n",outsample[i]));
                            #0.01;
                        end
                        $fwrite(fdebug,$sformatf("%1d\n",probe0));
                        $fwrite(fdebug,$sformatf("%1d\n",probe4));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                        $fwrite(fdebug,$sformatf("%1d\n",0));
                    end
 
                    $fclose(fd);
                    $fclose(fdebug);
                    $fclose(f);


                    // #100
                    // // for(int freq=205; freq<1495; freq = freq+2500) begin
                    // //     f = $fopen($sformatf("freqs/output_%0d_MHz_notch_%0d_MHz.txt", freq, notch), "w");
                    // //     fdebug = $fopen($sformatf("freqs/output_expanded_%0d_MHz_notch_%0d_MHz.txt", freq, notch), "w");
                    // //     fd = $fopen($sformatf("freqs/input_%1d_MHz.dat", freq),"r");

                    for(int in_count=0; in_count<20; in_count = in_count+1) begin
                        
                        fd = $fopen($sformatf("freqs/inputs/gauss_input_%1d_sigma_hanning_clipped_%0d.dat", GAUSS_NOISE_SIZE, in_count),"r");
                        if (THIS_DESIGN == "BIQUAD") begin : BIQUAD_GAUSS_OUT
                            f = $fopen($sformatf("freqs/outputs/output_gauss_%1d_trial_%0d_incremental_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                            fdebug = $fopen($sformatf("freqs/outputs/output_gauss_%1d_expanded_trial_%0d_incremental_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                            $monitor($sformatf("freqs/output_gauss_%1d_expanded_trial_%0d_incremental_notch_%0d_MHz.txt", GAUSS_NOISE_SIZE, in_count, notch));
                        end else begin: IIR_GAUSS_OUT
                            f = $fopen($sformatf("freqs/outputs/no_zero_output_gauss_%1d_trial_%0d_incremental_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                            fdebug = $fopen($sformatf("freqs/outputs/no_zero_output_gauss_%1d_expanded_trial_%0d_incremental_notch_%0d_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch, Q), "w");
                            $monitor($sformatf("freqs/outputs/no_zero_output_gauss_%1d_expanded_trial_%0d_notch_%0d_incremental_MHz_%1d.txt", GAUSS_NOISE_SIZE, in_count, notch,Q));
                            // code = $fgets(str, fd);
                        end

                        // $fwrite(f, "Hello World\n");
                        // #500
                        // $monitor("Beginning Stimulus");
                        code = 1;
                        // "Extra 'clearing out' of the biquad, probably not necessary"
                        // for(int clocks=0;clocks<4;clocks++) begin // We are expecting 8000 samples
                        //     @(posedge aclk);
                        //     for (int i=0; i<8; i++) begin
                        //         // Get the next inputs
                        //         samples[i] = 0;
                        //         // $monitor("Hello World in loop");
                        //         // $monitor($sformatf("sample is %1d", 0));
                        //         $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        //         #0.01;
                        //     end
                        //     $fwrite(fdebug,$sformatf("%1d\n",probe0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",probe4));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        // end
                        for(int clocks=0;clocks<10007;clocks++) begin // We are expecting 80064 samples, cut the end
                            @(posedge aclk);
                            #0.01;
                            for (int i=0; i<8; i++) begin
                                // Get the next inputs
                                code = $fgets(str, fd);
                                dummy = $sscanf(str, "%d", data_from_file);
                                samples[i] = data_from_file;
                                // $monitor("Hello World in loop");
                                // $monitor($sformatf("sample is %1d", data_from_file));
                                $fwrite(f,$sformatf("%1d\n",outsample[i]));
                                #0.01;
                            end
                            $fwrite(fdebug,$sformatf("%1d\n",probe0));
                            $fwrite(fdebug,$sformatf("%1d\n",probe4));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                            $fwrite(fdebug,$sformatf("%1d\n",0));
                        end
                        // for(int clocks=0;clocks<1000;clocks++) begin // We are expecting 8000 samples
                        //     @(posedge aclk);
                        //     #0.01;
                        //     for (int i=0; i<8; i++) begin
                        //         // Get the next inputs
                        //         samples[i] = 0;
                        //         // $monitor("Hello World in loop");
                        //         // $monitor($sformatf("sample is %1d", 0));
                        //         $fwrite(f,$sformatf("%1d\n",outsample[i]));
                        //         #0.01;
                        //     end
                        //     $fwrite(fdebug,$sformatf("%1d\n",probe0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",probe4));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        //     $fwrite(fdebug,$sformatf("%1d\n",0));
                        // end
                        $fclose(fd);
                        $fclose(fdebug);
                        $fclose(f);
                    end
                end
            end




            // @(posedge aclk);
            // #0.01;
            // samples[0] = 1;
            // samples[1] = 1;
            // samples[2] = 1;
            // samples[3] = 1;
            // samples[4] = 1;
            // samples[5] = 1;
            // samples[6] = 1;
            // samples[7] = 1;
            // @(posedge aclk);
            // #0.01;
            // samples[0] = 0;        
            // @(posedge aclk);
            // @(posedge aclk);
            // for (l=0;l<8;l=l+1) begin
            //     @(posedge aclk);
            //     #0.01;
            //     samples[l] = 1;
            //     @(posedge aclk);
            //     #0.01;
            //     samples[l] = 0;        
            //     @(posedge aclk);
            //     @(posedge aclk);
            // end            
        end
    end
    
endmodule
