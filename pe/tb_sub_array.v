`timescale 1ns/1ps

module tb_sub_array;
  localparam SA_R=8, SA_C=8, I_BITS=8, W_BITS=8;
  localparam PS_BITS=8+8+4;

  reg clk=0; always #5 clk=~clk;
  reg reset, mem_en, read_en;
  reg [2:0] row_l, col_l;
  reg [7:0] din;
  wire [7:0] dout;
  reg [I_BITS*SA_R-1:0] in_rows;
  wire [SA_C*PS_BITS-1:0] ps_flat;

  sub_array #(.I_BITS(I_BITS),.W_BITS(W_BITS),.SA_R(SA_R),.SA_C(SA_C)) dut(
    .clk(clk), .reset(reset),
    .mem_en(mem_en), .read_en(read_en),
    .row_addr_l(row_l), .col_addr_l(col_l),
    .mem_write_in(din), .mem_read_out(dout),
    .in_rows_flat(in_rows), .col_ps_flat(ps_flat)
  );

  integer r,c;

  initial begin
    reset=1; mem_en=0; read_en=0; row_l=0; col_l=0; din=0; in_rows=0;
    repeat(3) @(posedge clk);
    reset=0;
    $display("\n[TB] Reset done.");

    // -----------------------------------
    // 안전한 write 시퀀스 (2-cycle 유지)
    // -----------------------------------
    $display("[TB] Writing weights...");
    for (r=0;r<SA_R;r=r+1)
      for (c=0;c<SA_C;c=c+1) begin
        @(posedge clk);
        mem_en=1; read_en=0; row_l=r[2:0]; col_l=c[2:0]; din=r+c;
        @(posedge clk); // 유지
        mem_en=1; // 1-cycle 더 유지
        @(posedge clk);
        mem_en=0;
      end

    // -----------------------------------
    // Read check
    // -----------------------------------
    @(posedge clk);
    mem_en=1; read_en=1; row_l=3; col_l=5;
    repeat(3) @(posedge clk);
    $display("[TB] Read mem[3][5] = %0d (expected %0d)", dout, 8);
    mem_en=0;

    // -----------------------------------
    // Input vector
    // -----------------------------------
    for (r=0;r<SA_R;r=r+1)
      in_rows[(r+1)*8-1 -: 8] = r[7:0];

    @(posedge clk);
    repeat(1000) @(posedge clk);
    $display("[TB] Column Partial Sums:");
    for (c=0;c<SA_C;c=c+1)
      $display(" col[%0d] = %0d", c, ps_flat[(c+1)*PS_BITS-1 -: PS_BITS]);

    $finish;
  end
endmodule
