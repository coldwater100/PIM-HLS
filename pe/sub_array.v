module sub_array #(
  parameter I_BITS = 8,
  parameter W_BITS = 8,
  parameter SA_R   = 8,
  parameter SA_C   = 8
)(
  input  wire clk,
  input  wire reset,
  input  wire mem_en,
  input  wire read_en,
  input  wire [2:0] row_addr_l,
  input  wire [2:0] col_addr_l,
  input  wire [W_BITS-1:0] mem_write_in,
  output reg  [W_BITS-1:0] mem_read_out,
  input  wire [I_BITS*SA_R-1:0] in_rows_flat,
  output reg  [SA_C*(W_BITS+I_BITS+4)-1:0] col_ps_flat
);

  localparam ACC_BITS = W_BITS + I_BITS + 4;
  reg [W_BITS-1:0] mem [0:SA_R-1][0:SA_C-1];
  wire [I_BITS-1:0] in_row [0:SA_R-1];
  reg [ACC_BITS-1:0] col_ps [0:SA_C-1];

  // 입력 언팩
  genvar r;
  generate
    for (r=0; r<SA_R; r=r+1)
      assign in_row[r] = in_rows_flat[(r+1)*I_BITS-1 -: I_BITS];
  endgenerate

  // ================================
  // Write control latch (2-cycle safety)
  // ================================
  reg wr_en_d1, wr_en_d2;
  reg [W_BITS-1:0] wr_data_d1;
  reg [2:0] wr_row_d1, wr_col_d1;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      wr_en_d1 <= 0; wr_en_d2 <= 0;
      wr_data_d1 <= 0; wr_row_d1 <= 0; wr_col_d1 <= 0;
    end else begin
      wr_en_d1 <= (mem_en && !read_en);
      wr_en_d2 <= wr_en_d1;                // 1-cycle delay for ModelSim stability
      wr_data_d1 <= mem_write_in;
      wr_row_d1 <= row_addr_l;
      wr_col_d1 <= col_addr_l;
    end
  end

  // ================================
  // Memory read/write
  // ================================
  integer i,j;
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      for (i=0; i<SA_R; i=i+1)
        for (j=0; j<SA_C; j=j+1)
          mem[i][j] <= 0;
      mem_read_out <= 0;
    end else begin
      if (mem_en && read_en)
        mem_read_out <= mem[row_addr_l][col_addr_l];
      else if (wr_en_d2)
        mem[wr_row_d1][wr_col_d1] <= wr_data_d1;   // 확실히 한 클록 뒤에 write 실행
    end
  end

  // ================================
  // Simple combinational MAC (test only)
  // ================================
  integer c, k;
  reg [ACC_BITS-1:0] sum;
  always @(*) begin
    for (c=0; c<SA_C; c=c+1) begin
      sum = 0;
      for (k=0; k<SA_R; k=k+1)
        sum = sum + mem[k][c] * in_row[k];
      col_ps_flat[(c+1)*ACC_BITS-1 -: ACC_BITS] = sum;
    end
  end

endmodule
