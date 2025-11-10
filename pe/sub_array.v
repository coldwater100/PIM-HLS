`timescale 1ns / 1ps

module sub_array #(
    parameter XBAR_R = 3,           // Row 수
    parameter XBAR_C = 3,           // Column 수
    parameter W_BITS  = 8,          // Weight bit width
    parameter I_BITS  = 8,          // Input bit width
    parameter ACC_BITS = 32         // 누산기 bit width
)(
    input  wire clk,
    input  wire reset,
    input  wire mem_en,
    input  wire read_en,
    input  wire calc_en,
    input  wire [31:0] row_address,          // Row address
    input  wire [31:0] col_address,          // Column address
    input  wire [W_BITS-1:0] mem_write_in,   // Weight write data
    input  wire [I_BITS*XBAR_R-1:0] in_feat_flat, // Flattened input vector
    output reg  [W_BITS-1:0] mem_read_out,   // Weight read data
    output wire [ACC_BITS*XBAR_C-1:0] out_feat_flat, // Flattened output (auto width)
    output reg  available                    // Done flag
);

    // 내부 메모리
    reg [W_BITS-1:0] mem [0:XBAR_R-1][0:XBAR_C-1];
    reg [I_BITS-1:0] in_data [0:XBAR_R-1];
    reg [ACC_BITS-1:0] acc [0:XBAR_C-1];

    integer r, c, i, j;

    // 입력 벡터 언팩
    always @(*) begin
        for (r = 0; r < XBAR_R; r = r + 1)
            in_data[r] = in_feat_flat[I_BITS*(r+1)-1 -: I_BITS];
    end

    // 메모리 쓰기
    always @(posedge clk) begin
        if (mem_en && !read_en && !calc_en) begin
            mem[row_address][col_address] <= mem_write_in;
            // $display("[DBG] Wrote mem[%0d][%0d] = %0d", row_address, col_address, mem_write_in);
        end
    end

    // 메모리 읽기
    always @(posedge clk) begin
        if (read_en && !mem_en && !calc_en) begin
            mem_read_out <= mem[row_address][col_address];
            // $display("[DBG] Read mem[%0d][%0d] = %0d", row_address, col_address, mem_read_out);
        end
    end

    // Cross-bit AND + (i+j) shift 연산
    always @(posedge clk) begin
        if (reset) begin
            available <= 0;
            for (c = 0; c < XBAR_C; c = c + 1)
                acc[c] <= 0;
        end
        else if (calc_en) begin
            available <= 0;
            // $display("\n[DBG] ===== Cross-bit AND + (i+j) Shift Compute =====");
            for (c = 0; c < XBAR_C; c = c + 1) begin
                reg [ACC_BITS-1:0] psum;
                psum = 0;
                for (r = 0; r < XBAR_R; r = r + 1) begin
                    for (i = 0; i < I_BITS; i = i + 1) begin
                        for (j = 0; j < W_BITS; j = j + 1) begin
                            psum = psum + ((in_data[r][i] & mem[r][c][j]) << (i + j));
                        end
                    end
                end
                acc[c] <= psum;
                // $display("[DBG] col[%0d] psum = %0d", c, psum);
            end
            available <= 1;
            // $display("[DBG] === Cross-bit MAC Completed ===\n");
        end
    end

    // 출력 벡터 패킹
    genvar gc;
    generate
        for (gc = 0; gc < XBAR_C; gc = gc + 1) begin : PACK_OUT
            assign out_feat_flat[ACC_BITS*(gc+1)-1 -: ACC_BITS] = acc[gc];
        end
    endgenerate

endmodule
