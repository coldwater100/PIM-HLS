`timescale 1ns / 1ps

module tb_sub_array;
    parameter XBAR_R = 3;
    parameter XBAR_C = 3;
    parameter W_BITS  = 8;
    parameter I_BITS  = 8;
    parameter ACC_BITS = 32;

    // === DUT I/O ===
    reg clk;
    reg reset;
    reg mem_en, read_en, calc_en;
    reg [31:0] row_address;
    reg [31:0] col_address;
    reg [W_BITS-1:0] mem_write_in;
    reg [I_BITS*XBAR_R-1:0] in_feat_flat;

    wire [W_BITS-1:0] mem_read_out;
    wire [ACC_BITS*XBAR_C-1:0] out_feat_flat;
    wire available;

    integer r, c;

    // === DUT 인스턴스 ===
    sub_array #(
        .XBAR_R(XBAR_R),
        .XBAR_C(XBAR_C),
        .W_BITS(W_BITS),
        .I_BITS(I_BITS),
        .ACC_BITS(ACC_BITS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .mem_en(mem_en),
        .read_en(read_en),
        .calc_en(calc_en),
        .row_address(row_address),
        .col_address(col_address),
        .mem_write_in(mem_write_in),
        .in_feat_flat(in_feat_flat),
        .mem_read_out(mem_read_out),
        .out_feat_flat(out_feat_flat),
        .available(available)
    );

    // === Clock ===
    always #5 clk = ~clk;

    // === Testbench ===
    initial begin
        clk = 0;
        reset = 1;
        mem_en = 0; read_en = 0; calc_en = 0;
        row_address = 0; col_address = 0; mem_write_in = 0;
        in_feat_flat = 0;

        $display("\n[TB] Starting simulation...");
        #20 reset = 0;
        $display("[TB] Reset done.\n");

        // 1️⃣ Write weights
        $display("[TB] Writing 3x3 weight matrix W = [[1,2,3],[4,5,6],[7,8,9]] ...");
        for (r = 0; r < XBAR_R; r = r + 1)
            for (c = 0; c < XBAR_C; c = c + 1) begin
                @(posedge clk);
                mem_en = 1; read_en = 0; calc_en = 0;
                row_address = r; col_address = c;
                mem_write_in = (r * XBAR_C + c + 1); // 1~9
                @(posedge clk);
                mem_en = 0;
                $display("[DBG] Wrote mem[%0d][%0d] = %0d", r, c, mem_write_in);
            end
        $display("[TB] Write complete.\n");

        // 2️⃣ Read check
        @(posedge clk);
        read_en = 1; mem_en = 0; calc_en = 0;
        row_address = 1; col_address = 2;
        @(posedge clk);
        @(posedge clk);
        read_en = 0;
        $display("[TB] Read mem[1][2] = %0d (expected 6)\n", mem_read_out);

        // 3️⃣ Input vector
        in_feat_flat = {8'd3, 8'd2, 8'd1};
        $display("[TB] Input vector x = [1, 2, 3]\n");

        // 4️⃣ 계산식 출력 (display에 수식 추가)
        $display("-------------------------------------------------------------");
        $display("[TB] Matrix Multiplication : y = x * W");
        $display("    x = [1, 2, 3]");
        $display("    W = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]");
        $display("-------------------------------------------------------------");
        $display("    y0 = 1*1 + 2*4 + 3*7 = 30");
        $display("    y1 = 1*2 + 2*5 + 3*8 = 36");
        $display("    y2 = 1*3 + 2*6 + 3*9 = 42");
        $display("-------------------------------------------------------------");
        $display("    Expected output ≈ [30, 36, 42]");
        $display("-------------------------------------------------------------\n");

        // 5️⃣ 실제 연산 수행
        calc_en = 1;
        @(posedge clk);
        wait(available == 1);
        calc_en = 0;
        $display("[TB] Computation done!\n");

        // 6️⃣ 출력 확인
        for (c = 0; c < XBAR_C; c = c + 1) begin
            reg [ACC_BITS-1:0] col_val;
            col_val = out_feat_flat[ACC_BITS*(c+1)-1 -: ACC_BITS];
            $display("[TB] y[%0d] = %0d", c, col_val);
        end

        $display("\n[TB] ✅ Verification Summary");
        $display("[TB] Expected y = [30, 36, 42]");
        $display("[TB] Computed  y = values above (from Crossbar output)\n");

        #10 $finish;
    end
endmodule
