/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module integer_sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [63:0] radicand,
    output reg         busy,
    output reg         done,
    output reg  [31:0] root
);

  reg [63:0] operand;
  reg [65:0] remainder;
  reg [5:0] iteration;

  wire [65:0] shifted_remainder = {remainder[63:0], operand[63:62]};
  wire [65:0] trial_divisor = {32'b0, root, 2'b01};
  wire trial_succeeds = shifted_remainder >= trial_divisor;
  wire [65:0] next_remainder =
      trial_succeeds ? shifted_remainder - trial_divisor : shifted_remainder;
  wire [31:0] next_root = {root[30:0], trial_succeeds};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      operand <= 64'b0;
      remainder <= 66'b0;
      iteration <= 6'd0;
      busy <= 1'b0;
      done <= 1'b0;
      root <= 32'b0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        operand <= radicand;
        remainder <= 66'b0;
        iteration <= 6'd0;
        busy <= 1'b1;
        root <= 32'b0;
      end else if (busy) begin
        operand <= {operand[61:0], 2'b0};
        remainder <= next_remainder;
        root <= next_root;
        if (iteration == 6'd31) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          iteration <= iteration + 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
