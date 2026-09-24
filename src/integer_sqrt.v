/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module integer_sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [47:0] radicand,
    output reg         busy,
    output reg         done,
    output reg  [23:0] root
);

  reg [47:0] operand;
  reg [49:0] remainder;
  reg [4:0] iteration;

  wire [49:0] shifted_remainder = {remainder[47:0], operand[47:46]};
  wire [49:0] trial_divisor = {24'b0, root, 2'b01};
  wire trial_succeeds = shifted_remainder >= trial_divisor;
  wire [49:0] next_remainder =
      trial_succeeds ? shifted_remainder - trial_divisor : shifted_remainder;
  wire [23:0] next_root = {root[22:0], trial_succeeds};

  always @(posedge clk) begin
    if (!rst_n) begin
      operand <= 48'b0;
      remainder <= 50'b0;
      iteration <= 5'd0;
      busy <= 1'b0;
      done <= 1'b0;
      root <= 24'b0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        operand <= radicand;
        remainder <= 50'b0;
        iteration <= 5'd0;
        busy <= 1'b1;
        root <= 24'b0;
      end else if (busy) begin
        operand <= {operand[45:0], 2'b0};
        remainder <= next_remainder;
        root <= next_root;
        if (iteration == 5'd23) begin
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
