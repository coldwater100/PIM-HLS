`timescale 1ns/1ps

module pe #(
  parameter I_BITS = 8,
  parameter W_BITS = 8,
  parameter XBAR_R = 256,
  parameter XBAR_C = 256,
  parameter ADDER_IN_NUM = 8,
  parameter AD_NUM = 8
)(
  input  wire clk,
  input  wire reset,
  input  wire mem_en,
  input  wire read_en,
  input  wire calc_en,
  input  wire [31:0] row_address,
  input  wire [31:0] col_address,
  input  wire [7:0]  mem_write_in,
  input  wire [8*XBAR_R-1:0] in_feat_flat,
  output reg  [7:0]  mem_read_out,
  output wire [8*XBAR_C-1:0] out_feat_flat,
  output reg  available
);

  localparam ACC_BITS = W_BITS + I_BITS + 4;
  localparam R_BLKS = XBAR_R / ADDER_IN_NUM;
  localparam C_BLKS = XBAR_C / AD_NUM;

  reg [I_BITS*XBAR_R-1:0] act_buffer;
  wire [R_BLKS*C_BLKS*AD_NUM*ACC_BITS-1:0] sub_out_flat;
  wire [R_BLKS*C_BLKS-1:0] sub_done_flat;

  integer i, j;

  // -----------------------------
  // Input buffer latch
  // -----------------------------
  always @(posedge clk or posedge reset) begin
    if (reset)
      act_buffer <= 0;
    else if (calc_en)
      act_buffer <= in_feat_flat;
  end

  // -----------------------------
  // SubArray Instantiation
  // -----------------------------
  genvar r_blk, c_blk;
  generate
    for (r_blk=0; r_blk<R_BLKS; r_blk=r_blk+1) begin : R_TILE
      for (c_blk=0; c_blk<C_BLKS; c_blk=c_blk+1) begin : C_TILE
        localparam integer IDX_G = r_blk*C_BLKS + c_blk;
        sub_array #(
          .I_BITS(I_BITS),
          .W_BITS(W_BITS),
          .SA_R(ADDER_IN_NUM),
          .SA_C(AD_NUM)
        ) u_sub (
          .clk(clk),
          .reset(reset),
          .mem_en(mem_en),
          .read_en(read_en),
          .row_addr_l(row_address[$clog2(ADDER_IN_NUM)-1:0]),
          .col_addr_l(col_address[$clog2(AD_NUM)-1:0]),
          .mem_write_in(mem_write_in),
          .mem_read_out(),
          .in_rows_flat(act_buffer[(r_blk+1)*ADDER_IN_NUM*I_BITS-1 -: ADDER_IN_NUM*I_BITS]),
          .col_ps_flat(sub_out_flat[(IDX_G+1)*AD_NUM*ACC_BITS-1 -: AD_NUM*ACC_BITS]),
          .calc_done(sub_done_flat[IDX_G])
        );
      end
    end
  endgenerate

  // -----------------------------
  // AdderTree + ReQuant
  // -----------------------------
  wire [ACC_BITS-1:0] col_sum [0:XBAR_C-1];

  genvar c_blk_g, j_g, r_index_g;
  generate
    for (c_blk_g=0; c_blk_g<C_BLKS; c_blk_g=c_blk_g+1) begin : OUT_SUMS
      for (j_g=0; j_g<AD_NUM; j_g=j_g+1) begin : TREE
        localparam integer c_index = c_blk_g*AD_NUM + j_g;

        // Flattened adder inputs
        wire [R_BLKS*ACC_BITS-1:0] inputs_flat;

        for (r_index_g=0; r_index_g<R_BLKS; r_index_g=r_index_g+1) begin : IN_CON
          assign inputs_flat[(r_index_g+1)*ACC_BITS-1 -: ACC_BITS] =
            sub_out_flat[((r_index_g*C_BLKS + c_blk_g)*AD_NUM + j_g + 1)*ACC_BITS-1 -: ACC_BITS];
        end

        generic_adder_tree #(
          .INPUT_COUNT(R_BLKS),
          .DATA_WIDTH(ACC_BITS)
        ) u_tree (
          .clk(clk),
          .rst_n(~reset),
          .i_data(inputs_flat),
          .o_sum(col_sum[c_index])
        );
      end
    end
  endgenerate

  // -----------------------------
  // ReQuantization
  // -----------------------------
  genvar cc;
  generate
    for (cc=0; cc<XBAR_C; cc=cc+1) begin : REQ
      wire [7:0] qout;
      requant #(.IN_BITS(ACC_BITS), .OUT_BITS(8)) rq_inst (
        .in_val(col_sum[cc]),
        .out_val(qout)
      );
      assign out_feat_flat[(cc+1)*8-1 -: 8] = qout;
    end
  endgenerate

  // -----------------------------
  // Control logic
  // -----------------------------
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      mem_read_out <= 0;
      available <= 1;
    end else begin
      if (mem_en && read_en)
        mem_read_out <= mem_write_in;
      if (calc_en && &sub_done_flat)
        available <= 1;
      else if (calc_en)
        available <= 0;
    end
  end

endmodule
