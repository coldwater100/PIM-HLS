`timescale 1ns / 1ps

module sub_array #(
    parameter XBAR_R   = 3,    // Row 수
    parameter XBAR_C   = 3,    // Column 수
    parameter W_BITS   = 8,    // Weight bit width
    parameter I_BITS   = 8,    // Input bit width
    parameter ACC_BITS = 32    // 누산기 bit width
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

    // ===============================
    // 내부 메모리 및 레지스터 선언
    // ===============================
    reg [W_BITS-1:0] mem [0:XBAR_R-1][0:XBAR_C-1];    // 가중치 메모리
    reg [I_BITS-1:0] in_data [0:XBAR_R-1];            // 입력 데이터
    reg [ACC_BITS-1:0] acc [0:XBAR_C-1];              // 누산기

    integer r, c;

    // 입력 언팩 (in_feat_flat → in_data)
    always @(*) begin
        for (r = 0; r < XBAR_R; r = r + 1)
            in_data[r] = in_feat_flat[I_BITS*(r+1)-1 -: I_BITS];
    end

    // ===============================
    // 메모리 쓰기
    // ===============================
    always @(posedge clk) begin
        if (mem_en && !read_en && !calc_en)
            mem[row_address][col_address] <= mem_write_in;
    end

    // ===============================
    // 메모리 읽기
    // ===============================
    always @(posedge clk) begin
        if (read_en && !mem_en && !calc_en)
            mem_read_out <= mem[row_address][col_address];
    end


    // ========================================================
    // 병렬 Cross-bit AND + Shift → Adder Tree 기반 합산
    // ========================================================
    // Partial product 개수 = I_BITS * W_BITS
    localparam PP_COUNT = I_BITS * W_BITS;
    localparam PADDED_PP_COUNT = (1 << $clog2(PP_COUNT));  // 2의 거듭제곱 보정

    // 각 column별 partial product와 adder tree 출력
    wire [ACC_BITS-1:0] pp_data     [0:XBAR_C-1][0:PADDED_PP_COUNT-1];
    wire [ACC_BITS-1:0] adder_sum   [0:XBAR_C-1];

    genvar gc, gi, gj, gr;

    generate
        for (gc = 0; gc < XBAR_C; gc = gc + 1) begin : COL_BLOCK

            // 1️⃣ Partial Product 생성
            for (gr = 0; gr < XBAR_R; gr = gr + 1) begin : ROW_BLOCK
                for (gi = 0; gi < I_BITS; gi = gi + 1) begin : IN_BIT
                    for (gj = 0; gj < W_BITS; gj = gj + 1) begin : W_BIT
                        localparam IDX = gi*W_BITS + gj;
                        assign pp_data[gc][IDX] =
                            ((in_data[gr][gi] & mem[gr][gc][gj]) << (gi + gj));
                    end
                end
            end

            // 나머지 인덱스는 0으로 패딩 (adder tree 입력 수 맞춤)
            for (gi = PP_COUNT; gi < PADDED_PP_COUNT; gi = gi + 1) begin : PAD
                assign pp_data[gc][gi] = 0;
            end

            // 2️⃣ Adder Tree 인스턴스
            generic_adder_tree #(
                .INPUT_COUNT(PADDED_PP_COUNT),
                .DATA_WIDTH(ACC_BITS)
            ) u_adder_tree (
                .clk(clk),
                .rst_n(~reset),
                .i_data(pp_data[gc]),
                .o_sum(adder_sum[gc])
            );

        end
    endgenerate


    // ========================================================
    // 3️⃣ 출력 누산기 및 상태 플래그
    // ========================================================
    always @(posedge clk) begin
        if (reset) begin
            available <= 0;
            for (c = 0; c < XBAR_C; c = c + 1)
                acc[c] <= 0;
        end
        else if (calc_en) begin
            for (c = 0; c < XBAR_C; c = c + 1)
                acc[c] <= adder_sum[c];  // adder tree 결과 저장
            available <= 1;
        end
    end


    // ========================================================
    // 4️⃣ 출력 벡터 패킹 (acc → out_feat_flat)
    // ========================================================
    genvar gc_pack;
    generate
        for (gc_pack = 0; gc_pack < XBAR_C; gc_pack = gc_pack + 1) begin : PACK_OUT
            assign out_feat_flat[ACC_BITS*(gc_pack+1)-1 -: ACC_BITS] = acc[gc_pack];
        end
    endgenerate

endmodule
