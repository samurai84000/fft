module fft_top (
    input  logic        clk,
    input  logic        rst_n,

    // Input FIFO write interface (from driver)
    output logic        in_real_full,
    input  logic        in_real_wr_en,
    input  logic [31:0] in_real_din,

    output logic        in_imag_full,
    input  logic        in_imag_wr_en,
    input  logic [31:0] in_imag_din,

    // Output FIFO read interface (to monitor)
    output logic        out_real_empty,
    input  logic        out_real_rd_en,
    output logic [31:0] out_real_dout,

    output logic        out_imag_empty,
    input  logic        out_imag_rd_en,
    output logic [31:0] out_imag_dout
);

    // FFT Core Interconnects
    logic [31:0] core_in_re_data, core_in_im_data;
    logic        core_in_re_empty, core_in_im_empty;
    logic        core_in_re_rd,    core_in_im_rd;

    logic [31:0] core_out_re_data, core_out_im_data;
    logic        core_out_re_full, core_out_im_full;
    logic        core_out_re_wr,   core_out_im_wr;

    fft fft_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        // Real Input
        .in_real_empty  (core_in_re_empty),
        .in_real_dout   (core_in_re_data),
        .in_real_rd_en  (core_in_re_rd),
        // Imag Input
        .in_imag_empty  (core_in_im_empty),
        .in_imag_dout   (core_in_im_data),
        .in_imag_rd_en  (core_in_im_rd),
        // Real Output
        .out_real_full  (core_out_re_full),
        .out_real_wr_en (core_out_re_wr),
        .out_real_din   (core_out_re_data),
        // Imag Output
        .out_imag_full  (core_out_im_full),
        .out_imag_wr_en (core_out_im_wr),
        .out_imag_din   (core_out_im_data)
    );

    // Input FIFOs
    fifo #(.data_width(32), .buffer_size(16)) fifo_in_re (
        .rst(rst_n), .wr_clk(clk), .rd_clk(clk),
        .wr_en(in_real_wr_en), .din(in_real_din), .full(in_real_full),
        .rd_en(core_in_re_rd), .dout(core_in_re_data), .empty(core_in_re_empty)
    );

    fifo #(.data_width(32), .buffer_size(16)) fifo_in_im (
        .rst(rst_n), .wr_clk(clk), .rd_clk(clk),
        .wr_en(in_imag_wr_en), .din(in_imag_din), .full(in_imag_full),
        .rd_en(core_in_im_rd), .dout(core_in_im_data), .empty(core_in_im_empty)
    );

    // Output FIFOs
    fifo #(.data_width(32), .buffer_size(16)) fifo_out_re (
        .rst(rst_n), .wr_clk(clk), .rd_clk(clk),
        .wr_en(core_out_re_wr), .din(core_out_re_data), .full(core_out_re_full),
        .rd_en(out_real_rd_en), .dout(out_real_dout), .empty(out_real_empty)
    );

    fifo #(.data_width(32), .buffer_size(16)) fifo_out_im (
        .rst(rst_n), .wr_clk(clk), .rd_clk(clk),
        .wr_en(core_out_im_wr), .din(core_out_im_data), .full(core_out_im_full),
        .rd_en(out_imag_rd_en), .dout(out_imag_dout), .empty(out_imag_empty)
    );

endmodule