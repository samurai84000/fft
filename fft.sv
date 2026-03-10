module fft
#(
    parameter DATA_WIDTH = 32,
    parameter N          = 16,
    parameter NUM_STAGES = 4,
    parameter BITS       = 14
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // Input Interface
    input  logic        in_real_empty,
    input  logic [DATA_WIDTH-1:0] in_real_dout,
    output logic        in_real_rd_en,
    
    input  logic        in_imag_empty,
    input  logic [DATA_WIDTH-1:0] in_imag_dout,
    output logic        in_imag_rd_en,

    // Output Interface
    input  logic        out_real_full,
    output logic        out_real_wr_en,
    output logic [DATA_WIDTH-1:0] out_real_din,  
    
    input  logic        out_imag_full,
    output logic        out_imag_wr_en,
    output logic [DATA_WIDTH-1:0] out_imag_din
);

    typedef enum logic [2:0] { 
        ST_IDLE, 
        ST_LOAD, 
        ST_COMPUTE_RD, 
        ST_COMPUTE_MUL, 
        ST_COMPUTE_DQ, 
        ST_COMPUTE_WB, 
        ST_WRITE 
    } state_t;
    
    state_t state_r, state_n;

    // Bit-reversal permutation table
    localparam logic [3:0] BIT_REV_TABLE [0:15] = '{
        4'd0,  4'd8,  4'd4,  4'd12,
        4'd2,  4'd10, 4'd6,  4'd14,
        4'd1,  4'd9,  4'd5,  4'd13,
        4'd3,  4'd11, 4'd7,  4'd15
    };

    // Twiddle factors
    localparam signed [DATA_WIDTH-1:0] TWIDDLE_REAL [0:7] = '{
        32'sh00004000, 32'sh00003B20, 32'sh00002D41, 32'sh0000187D,
        32'sh00000000, 32'shFFFFE783, 32'shFFFFD2BF, 32'shFFFFC4E0
    };
    localparam signed [DATA_WIDTH-1:0] TWIDDLE_IMAG [0:7] = '{
        32'sh00000000, 32'shFFFFE783, 32'shFFFFD2BF, 32'shFFFFC4E0,
        32'shFFFFC000, 32'shFFFFC4E0, 32'shFFFFD2BF, 32'shFFFFE783
    };

    logic [3:0] sample_cnt_r, sample_cnt_n;
    logic [1:0] stage_idx_r,  stage_idx_n;
    logic [2:0] bfly_idx_r,   bfly_idx_n;

    // Internal Memory
    logic signed [DATA_WIDTH-1:0] mem_real_r [0:N-1], mem_real_n [0:N-1];
    logic signed [DATA_WIDTH-1:0] mem_imag_r [0:N-1], mem_imag_n [0:N-1];

    // Pipeline Registers: Stage 1 (Read)
    logic signed [DATA_WIDTH-1:0] pipe1_in1_re_r, pipe1_in1_re_n;
    logic signed [DATA_WIDTH-1:0] pipe1_in1_im_r, pipe1_in1_im_n;
    logic signed [DATA_WIDTH-1:0] pipe1_in2_re_r, pipe1_in2_re_n;
    logic signed [DATA_WIDTH-1:0] pipe1_in2_im_r, pipe1_in2_im_n;
    logic signed [DATA_WIDTH-1:0] pipe1_tw_re_r,  pipe1_tw_re_n;
    logic signed [DATA_WIDTH-1:0] pipe1_tw_im_r,  pipe1_tw_im_n;
    logic [3:0] pipe1_addr1_r, pipe1_addr1_n;
    logic [3:0] pipe1_addr2_r, pipe1_addr2_n;

    // Pipeline Registers: Stage 2 (Multiply)
    logic signed [63:0] pipe2_prod_re_re_r, pipe2_prod_re_re_n;
    logic signed [63:0] pipe2_prod_im_im_r, pipe2_prod_im_im_n;
    logic signed [63:0] pipe2_prod_re_im_r, pipe2_prod_re_im_n;
    logic signed [63:0] pipe2_prod_im_re_r, pipe2_prod_im_re_n;
    logic signed [DATA_WIDTH-1:0] pipe2_in1_re_r, pipe2_in1_re_n;
    logic signed [DATA_WIDTH-1:0] pipe2_in1_im_r, pipe2_in1_im_n;
    logic [3:0] pipe2_addr1_r, pipe2_addr1_n;
    logic [3:0] pipe2_addr2_r, pipe2_addr2_n;

    // Pipeline Registers: Stage 3 (Dequantize)
    logic signed [DATA_WIDTH-1:0] pipe3_v_re_r, pipe3_v_re_n;
    logic signed [DATA_WIDTH-1:0] pipe3_v_im_r, pipe3_v_im_n;
    logic signed [DATA_WIDTH-1:0] pipe3_in1_re_r, pipe3_in1_re_n;
    logic signed [DATA_WIDTH-1:0] pipe3_in1_im_r, pipe3_in1_im_n;
    logic [3:0] pipe3_addr1_r, pipe3_addr1_n;
    logic [3:0] pipe3_addr2_r, pipe3_addr2_n;

    // Combinational logic for addressing
    logic [3:0] bfly_addr1, bfly_addr2;
    logic [2:0] tw_step_j;
    logic [2:0] tw_map_idx;
    
    assign tw_map_idx = tw_step_j << (2'd3 - stage_idx_r);

    // Butterfly Multiplier Wires
    logic signed [63:0] mult_re_re_w, mult_im_im_w, mult_re_im_w, mult_im_re_w;
    assign mult_re_re_w = pipe1_tw_re_r * pipe1_in2_re_r;
    assign mult_im_im_w = pipe1_tw_im_r * pipe1_in2_im_r;
    assign mult_re_im_w = pipe1_tw_re_r * pipe1_in2_im_r;
    assign mult_im_re_w = pipe1_tw_im_r * pipe1_in2_re_r;

    function automatic logic signed [31:0] dequantize(input logic signed [63:0] val);
        logic signed [63:0] rounded;
        rounded = val + 64'sd8192;
        if (rounded >= 0)
            return rounded[31+BITS:BITS];
        else
            if (rounded[BITS-1:0] != '0)
                return (rounded >>> BITS) + 32'sd1;
            else
                return rounded >>> BITS;
    endfunction

    // V calculation (Intermediate result of complex mult)
    logic signed [DATA_WIDTH-1:0] v_re_w, v_im_w;
    assign v_re_w = dequantize(pipe2_prod_re_re_r) - dequantize(pipe2_prod_im_im_r);
    assign v_im_w = dequantize(pipe2_prod_re_im_r) + dequantize(pipe2_prod_im_re_r);

    // Butterfly Output Logic
    logic signed [DATA_WIDTH-1:0] res1_re_w, res1_im_w;
    logic signed [DATA_WIDTH-1:0] res2_re_w, res2_im_w;
    assign res1_re_w = pipe3_in1_re_r + pipe3_v_re_r;
    assign res1_im_w = pipe3_in1_im_r + pipe3_v_im_r;
    assign res2_re_w = pipe3_in1_re_r - pipe3_v_re_r;
    assign res2_im_w = pipe3_in1_im_r - pipe3_v_im_r;

    // Sequential Block
    always_ff @(posedge clk or posedge rst_n) begin
        if (rst_n) begin
            state_r         <= ST_IDLE;
            sample_cnt_r    <= '0;
            stage_idx_r     <= '0;
            bfly_idx_r      <= '0;
            // Clear pipeline and memory...
            // (Keeping logic same as original reset block)
            pipe1_in1_re_r  <= '0; pipe1_in1_im_r  <= '0;
            pipe1_in2_re_r  <= '0; pipe1_in2_im_r  <= '0;
            pipe1_tw_re_r   <= '0; pipe1_tw_im_r   <= '0;
            pipe1_addr1_r   <= '0; pipe1_addr2_r   <= '0;
            pipe2_prod_re_re_r <= '0; pipe2_prod_im_im_r <= '0;
            pipe2_prod_re_im_r <= '0; pipe2_prod_im_re_r <= '0;
            pipe2_in1_re_r  <= '0; pipe2_in1_im_r  <= '0;
            pipe2_addr1_r   <= '0; pipe2_addr2_r   <= '0;
            pipe3_v_re_r    <= '0; pipe3_v_im_r    <= '0;
            pipe3_in1_re_r  <= '0; pipe3_in1_im_r  <= '0;
            pipe3_addr1_r   <= '0; pipe3_addr2_r   <= '0;
            for (int i = 0; i < N; i++) begin
                mem_real_r[i] <= '0; mem_imag_r[i] <= '0;
            end
        end else begin
            state_r         <= state_n;
            sample_cnt_r    <= sample_cnt_n;
            stage_idx_r     <= stage_idx_n;
            bfly_idx_r      <= bfly_idx_n;
            pipe1_in1_re_r  <= pipe1_in1_re_n;
            pipe1_in1_im_r  <= pipe1_in1_im_n;
            pipe1_in2_re_r  <= pipe1_in2_re_n;
            pipe1_in2_im_r  <= pipe1_in2_im_n;
            pipe1_tw_re_r   <= pipe1_tw_re_n;
            pipe1_tw_im_r   <= pipe1_tw_im_n;
            pipe1_addr1_r   <= pipe1_addr1_n;
            pipe1_addr2_r   <= pipe1_addr2_n;
            pipe2_prod_re_re_r <= pipe2_prod_re_re_n;
            pipe2_prod_im_im_r <= pipe2_prod_im_im_n;
            pipe2_prod_re_im_r <= pipe2_prod_re_im_n;
            pipe2_prod_im_re_r <= pipe2_prod_im_re_n;
            pipe2_in1_re_r  <= pipe2_in1_re_n;
            pipe2_in1_im_r  <= pipe2_in1_im_n;
            pipe2_addr1_r   <= pipe2_addr1_n;
            pipe2_addr2_r   <= pipe2_addr2_n;
            pipe3_v_re_r    <= pipe3_v_re_n;
            pipe3_v_im_r    <= pipe3_v_im_n;
            pipe3_in1_re_r  <= pipe3_in1_re_n;
            pipe3_in1_im_r  <= pipe3_in1_im_n;
            pipe3_addr1_r   <= pipe3_addr1_n;
            pipe3_addr2_r   <= pipe3_addr2_n;
            for (int i = 0; i < N; i++) begin
                mem_real_r[i] <= mem_real_n[i];
                mem_imag_r[i] <= mem_imag_n[i];
            end
        end
    end

    // Next State Logic
    always_comb begin
        // Defaults
        state_n         = state_r;
        sample_cnt_n    = sample_cnt_r;
        stage_idx_n     = stage_idx_r;
        bfly_idx_n      = bfly_idx_r;
        
        pipe1_in1_re_n  = pipe1_in1_re_r; pipe1_in1_im_n  = pipe1_in1_im_r;
        pipe1_in2_re_n  = pipe1_in2_re_r; pipe1_in2_im_n  = pipe1_in2_im_r;
        pipe1_tw_re_n   = pipe1_tw_re_r;  pipe1_tw_im_n   = pipe1_tw_im_r;
        pipe1_addr1_n   = pipe1_addr1_r;  pipe1_addr2_n   = pipe1_addr2_r;

        pipe2_prod_re_re_n = pipe2_prod_re_re_r; pipe2_prod_im_im_n = pipe2_prod_im_im_r;
        pipe2_prod_re_im_n = pipe2_prod_re_im_r; pipe2_prod_im_re_n = pipe2_prod_im_re_r;
        pipe2_in1_re_n  = pipe2_in1_re_r; pipe2_in1_im_n  = pipe2_in1_im_r;
        pipe2_addr1_n   = pipe2_addr1_r;  pipe2_addr2_n   = pipe2_addr2_r;

        pipe3_v_re_n    = pipe3_v_re_r;   pipe3_v_im_n    = pipe3_v_im_r;
        pipe3_in1_re_n  = pipe3_in1_re_r; pipe3_in1_im_n  = pipe3_in1_im_r;
        pipe3_addr1_n   = pipe3_addr1_r;  pipe3_addr2_n   = pipe3_addr2_r;

        mem_real_n = mem_real_r;
        mem_imag_n = mem_imag_r;

        in_real_rd_en = 1'b0; in_imag_rd_en = 1'b0;
        out_real_wr_en = 1'b0; out_imag_wr_en = 1'b0;
        out_real_din = '0; out_imag_din = '0;

        // Butterfly address mapping
        case (stage_idx_r)
            2'd0: begin bfly_addr1 = {bfly_idx_r, 1'b0}; bfly_addr2 = {bfly_idx_r, 1'b1}; tw_step_j = 3'd0; end
            2'd1: begin bfly_addr1 = {bfly_idx_r[2:1], 1'b0, bfly_idx_r[0]}; bfly_addr2 = {bfly_idx_r[2:1], 1'b1, bfly_idx_r[0]}; tw_step_j = {2'd0, bfly_idx_r[0]}; end
            2'd2: begin bfly_addr1 = {bfly_idx_r[2], 1'b0, bfly_idx_r[1:0]}; bfly_addr2 = {bfly_idx_r[2], 1'b1, bfly_idx_r[1:0]}; tw_step_j = {1'd0, bfly_idx_r[1:0]}; end
            2'd3: begin bfly_addr1 = {1'b0, bfly_idx_r}; bfly_addr2 = {1'b1, bfly_idx_r}; tw_step_j = bfly_idx_r; end
            default: {bfly_addr1, bfly_addr2, tw_step_j} = '0;
        endcase

        case (state_r)
            ST_IDLE: begin
                if (!in_real_empty && !in_imag_empty) begin
                    sample_cnt_n = '0;
                    state_n = ST_LOAD;
                end
            end

            ST_LOAD: begin
                if (!in_real_empty && !in_imag_empty) begin
                    in_real_rd_en = 1'b1;
                    in_imag_rd_en = 1'b1;
                    mem_real_n[BIT_REV_TABLE[sample_cnt_r]] = signed'(in_real_dout);
                    mem_imag_n[BIT_REV_TABLE[sample_cnt_r]] = signed'(in_imag_dout);

                    if (sample_cnt_r == 4'd15) begin
                        stage_idx_n = '0;
                        bfly_idx_n  = '0;
                        state_n     = ST_COMPUTE_RD;
                    end else begin
                        sample_cnt_n = sample_cnt_r + 4'd1;
                    end
                end
            end

            ST_COMPUTE_RD: begin
                pipe1_in1_re_n = mem_real_r[bfly_addr1];
                pipe1_in1_im_n = mem_imag_r[bfly_addr1];
                pipe1_in2_re_n = mem_real_r[bfly_addr2];
                pipe1_in2_im_n = mem_imag_r[bfly_addr2];
                pipe1_tw_re_n  = TWIDDLE_REAL[tw_map_idx];
                pipe1_tw_im_n  = TWIDDLE_IMAG[tw_map_idx];
                pipe1_addr1_n  = bfly_addr1;
                pipe1_addr2_n  = bfly_addr2;
                state_n        = ST_COMPUTE_MUL;
            end

            ST_COMPUTE_MUL: begin
                pipe2_prod_re_re_n = mult_re_re_w;
                pipe2_prod_im_im_n = mult_im_im_w;
                pipe2_prod_re_im_n = mult_re_im_w;
                pipe2_prod_im_re_n = mult_im_re_w;
                pipe2_in1_re_n     = pipe1_in1_re_r;
                pipe2_in1_im_n     = pipe1_in1_im_r;
                pipe2_addr1_n      = pipe1_addr1_r;
                pipe2_addr2_n      = pipe1_addr2_r;
                state_n            = ST_COMPUTE_DQ;
            end

            ST_COMPUTE_DQ: begin
                pipe3_v_re_n    = v_re_w;
                pipe3_v_im_n    = v_im_w;
                pipe3_in1_re_n  = pipe2_in1_re_r;
                pipe3_in1_im_n  = pipe2_in1_im_r;
                pipe3_addr1_n   = pipe2_addr1_r;
                pipe3_addr2_n   = pipe2_addr2_r;
                state_n         = ST_COMPUTE_WB;
            end

            ST_COMPUTE_WB: begin
                mem_real_n[pipe3_addr1_r] = res1_re_w;
                mem_imag_n[pipe3_addr1_r] = res1_im_w;
                mem_real_n[pipe3_addr2_r] = res2_re_w;
                mem_imag_n[pipe3_addr2_r] = res2_im_w;

                if (bfly_idx_r == 3'd7) begin
                    bfly_idx_n = '0;
                    if (stage_idx_r == 2'd3) begin
                        sample_cnt_n = '0;
                        state_n      = ST_WRITE;
                    end else begin
                        stage_idx_n = stage_idx_r + 2'd1;
                        state_n     = ST_COMPUTE_RD;
                    end
                end else begin
                    bfly_idx_n = bfly_idx_r + 3'd1;
                    state_n    = ST_COMPUTE_RD;
                end
            end

            ST_WRITE: begin
                if (!out_real_full && !out_imag_full) begin
                    out_real_wr_en = 1'b1;
                    out_imag_wr_en = 1'b1;
                    out_real_din   = mem_real_r[sample_cnt_r];
                    out_imag_din   = mem_imag_r[sample_cnt_r];
                    if (sample_cnt_r == 4'd15) state_n = ST_IDLE;
                    else sample_cnt_n = sample_cnt_r + 4'd1;
                end
            end

            default: state_n = ST_IDLE;
        endcase
    end
endmodule