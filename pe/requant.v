//===========================================================
// Module : requant
// Function : Fixed-point scaling and clipping to 8-bit
//===========================================================
module requant #(
  parameter IN_BITS  = 20, // e.g. W_BITS + I_BITS + 4
  parameter OUT_BITS = 8
)(
  input  wire [IN_BITS-1:0] in_val,
  output wire [OUT_BITS-1:0] out_val
);
  // 간단한 스케일링 및 saturation clipping
  wire [IN_BITS-1:0] scaled = in_val >> (IN_BITS - OUT_BITS);
  assign out_val = (scaled > {OUT_BITS{1'b1}}) ? {OUT_BITS{1'b1}} : scaled[OUT_BITS-1:0];
endmodule
