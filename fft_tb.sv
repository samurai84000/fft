`timescale 1ns/1ns

module fft_tb;

    //==========================================================================
    // Parameters
    //==========================================================================
    localparam CLK_PERIOD   = 10; // 100 MHz [cite: 119, 120]
    localparam N            = 16; 
    localparam TOLERANCE    = 0;  // bit-true: 0 tolerance [cite: 121]

    //==========================================================================
    // Signals
    //==========================================================================
    logic        clk;   
    logic        rst_n; 

    // Input FIFO write interface
    logic        in_re_full;  
    logic        in_re_wr_en; 
    logic [31:0] in_re_din;  

    logic        in_im_full;  
    logic        in_im_wr_en; 
    logic [31:0] in_im_din;   

    // Output FIFO read interface
    logic        out_re_empty; 
    logic        out_re_rd_en; 
    logic [31:0] out_re_dout; 

    logic        out_im_empty; 
    logic        out_im_rd_en; 
    logic [31:0] out_im_dout;  

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    fft_top dut (
        .clk            (clk),          
        .rst_n          (rst_n),        
        .in_real_full   (in_re_full),   
        .in_real_wr_en  (in_re_wr_en),  
        .in_real_din    (in_re_din),  
        .in_imag_full   (in_im_full),   
        .in_imag_wr_en  (in_im_wr_en),  
        .in_imag_din    (in_im_din),    
        .out_real_empty (out_re_empty), 
        .out_real_rd_en (out_re_rd_en), 
        .out_real_dout  (out_re_dout),  
        .out_imag_empty (out_im_empty), 
        .out_imag_rd_en (out_im_rd_en),
        .out_imag_dout  (out_im_dout)   
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial clk = 0; 
    always #(CLK_PERIOD/2) clk = ~clk; 

    //==========================================================================
    // Test Data Storage
    //==========================================================================
    logic [31:0] in_re_data   [0:N-1]; 
    logic [31:0] in_im_data   [0:N-1]; 
    logic [31:0] out_re_expected [0:N-1]; 
    logic [31:0] out_im_expected [0:N-1]; 

    //==========================================================================
    // Statistics
    //==========================================================================
    int pass_count; 
    int fail_count; 
    int max_re_err;
    int max_im_err; 

    //==========================================================================
    // Main Test
    //==========================================================================
    initial begin
        // Load test data
        $readmemh("fft_in_real.txt",  in_re_data); 
        $readmemh("fft_in_imag.txt",  in_im_data); 
        $readmemh("fft_out_real.txt", out_re_expected); 
        $readmemh("fft_out_imag.txt", out_im_expected); 

        // Initialize
        rst_n         = 1; 
        in_re_wr_en   = 0; 
        in_im_wr_en   = 0; 
        in_re_din     = 0; 
        in_im_din     = 0; 
        out_re_rd_en  = 0; 
        out_im_rd_en  = 0; 
        pass_count    = 0; 
        fail_count    = 0; 
        max_re_err    = 0; 
        max_im_err    = 0; 

        // Reset
        repeat (5) @(posedge clk); 
        rst_n = 0;
        repeat (2) @(posedge clk); 

        $display("========================================");
        $display("  FFT Testbench — %0d-point FFT", N);
        $display("========================================"); 

        // --- Write all 16 inputs into FIFOs ---
        for (int i = 0; i < N; i++) begin
            @(posedge clk); 
            wait (!in_re_full && !in_im_full);
            in_re_wr_en = 1; 
            in_im_wr_en = 1;
            in_re_din   = in_re_data[i];
            in_im_din   = in_im_data[i]; 
            @(posedge clk); 
            in_re_wr_en = 0; 
            in_im_wr_en = 0;
        end

        $display("  All %0d inputs written to FIFOs.", N);

        // --- Read and compare all 16 outputs ---
        for (int i = 0; i < N; i++) begin
            // Wait for output to appear
            wait (!out_re_empty && !out_im_empty); 
            @(posedge clk); 
            out_re_rd_en = 1; 
            out_im_rd_en = 1;

            // Capture value and compare
            begin
                automatic int re_err = int'(signed'(out_re_dout)) - int'(signed'(out_re_expected[i])); 
                automatic int im_err = int'(signed'(out_im_dout)) - int'(signed'(out_im_expected[i])); 
                automatic int abs_re_err = (re_err < 0) ? -re_err : re_err;
                automatic int abs_im_err = (im_err < 0) ? -im_err : im_err; 

                if (abs_re_err > max_re_err) max_re_err = abs_re_err; 
                if (abs_im_err > max_im_err) max_im_err = abs_im_err;

                if (abs_re_err <= TOLERANCE && abs_im_err <= TOLERANCE) begin
                    pass_count++; 
                end
                else begin
                    fail_count++; 
                    $display("FAIL [%0d]: real: got=%08h exp=%08h (err=%0d) | imag: got=%08h exp=%08h (err=%0d)",
                        i,
                        out_re_dout, out_re_expected[i], re_err,
                        out_im_dout, out_im_expected[i], im_err); 
                end
            end

            @(posedge clk); 
            out_re_rd_en = 0;
            out_im_rd_en = 0;
        end

        // --- Summary ---
        $display(""); 
        $display("========================================"); 
        $display("  Results Summary");
        $display("========================================"); 
        $display("  Total:    %0d", N);
        $display("  PASS:     %0d", pass_count);
        $display("  FAIL:     %0d", fail_count); 
        $display("  Max real error: %0d LSB", max_re_err); 
        $display("  Max imag error: %0d LSB", max_im_err); 
        $display("========================================"); 
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***"); 
        else
            $display("*** %0d TESTS FAILED ***", fail_count); 

        $finish;
    end

endmodule
