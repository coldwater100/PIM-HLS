`timescale 1ns/1ps

module tb_pe;

  // -----------------------------
  // Parameter Definition
  // -----------------------------
  localparam I_BITS = 8;
  localparam W_BITS = 8;
  localparam XBAR_R = 256;
  localparam XBAR_C = 256;
  localparam ADDER_IN_NUM = 8;
  localparam AD_NUM = 8;

  // -----------------------------
  // DUT I/O
  // -----------------------------
  reg clk = 0;
  always #5 clk = ~clk;

  reg reset;
  reg mem_en;
  reg read_en;
  reg calc_en;
  reg [31:0] row_addr;
  reg [31:0] col_addr;
  reg [7:0] mem_write_in;
  wire [7:0] mem_read_out;
  reg [8*XBAR_R-1:0] in_feat_flat;
  wire [8*XBAR_C-1:0] out_feat_flat;
  wire available;

  // -----------------------------
  // DUT Instance
  // -----------------------------
  pe #(
    .I_BITS(I_BITS),
    .W_BITS(W_BITS),
    .XBAR_R(XBAR_R),
    .XBAR_C(XBAR_C),
    .ADDER_IN_NUM(ADDER_IN_NUM),
    .AD_NUM(AD_NUM)
  ) dut (
    .clk(clk),
    .reset(reset),
    .mem_en(mem_en),
    .read_en(read_en),
    .calc_en(calc_en),
    .row_address(row_addr),
    .col_address(col_addr),
    .mem_write_in(mem_write_in),
    .mem_read_out(mem_read_out),
    .in_feat_flat(in_feat_flat),
    .out_feat_flat(out_feat_flat),
    .available(available)
  );

  // -----------------------------
  // Procedural Variables
  // -----------------------------
  integer r, c;

  // -----------------------------
  // Test Procedure
  // -----------------------------
  initial begin
    $display("\n[TB] ====== Start PE Integrated Test ======\n");
    reset = 1; mem_en=0; read_en=0; calc_en=0;
    row_addr=0; col_addr=0; mem_write_in=0; in_feat_flat=0;
    repeat(5) @(posedge clk);
    reset = 0;
    $display("[TB] Reset complete.\n");

    // -----------------------------------
    // [TB] Writing weights (only 2 SubArrays)
    // -----------------------------------
    $display("[TB] Writing weights into 2 subarrays...");

    // 예: 첫 번째 SubArray (0~SA_R-1, 0~SA_C-1)
    //     두 번째 SubArray (SA_R~2*SA_R-1, 0~SA_C-1)
    for (sr = 0; sr < 2; sr = sr + 1) begin
    for (r = 0; r < SA_R; r = r + 1) begin
        for (c = 0; c < SA_C; c = c + 1) begin
        @(posedge clk);
        mem_en = 1;
        read_en = 0;
        row_l = (r + sr*SA_R)[2:0]; // SubArray 오프셋 반영
        col_l = c[2:0];
        din   = (r + c + sr*SA_R) & 8'hFF;

        @(posedge clk); // 유지
        mem_en = 1;     // 1-cycle 더 유지
        @(posedge clk);
        mem_en = 0;
        end
    end
    end


    // -------------------------------------
    // Read Sample Memory Value
    // -------------------------------------
    @(posedge clk);
    row_addr=3; col_addr=5;
    mem_en=1; read_en=1;
    @(posedge clk);
    mem_en=0;
    $display("[TB] Read mem[3][5] = %0d (expected %0d)", mem_read_out, (3+5));

    // -------------------------------------
    // Set Input Activation Vector
    // -------------------------------------
    for (r=0; r<XBAR_R; r=r+1)
      in_feat_flat[(r+1)*8-1 -: 8] = r[7:0];
    @(posedge clk);

    // -------------------------------------
    // Start Computation
    // -------------------------------------
    $display("[TB] Starting Computation...");
    calc_en=1;
    @(posedge clk);
    calc_en=0;

    // Wait until computation completes
    wait(available==1);
    $display("[TB] Computation finished.\n");

    // -------------------------------------
    // Print Outputs (first 8 Columns)
    // -------------------------------------
    $display("[TB] Column Outputs (Requantized):");
    for (c=0; c<8; c=c+1)
      $display("  out_feat[%0d] = %0d", c, out_feat_flat[(c+1)*8-1 -: 8]);

    $display("\n[TB] ====== Simulation Done ======\n");
    $finish;
  end
endmodule
