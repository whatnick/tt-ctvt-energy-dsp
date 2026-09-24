/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module serial_multiplier (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [23:0] operand_a,
    input  wire signed [23:0] operand_b,
    output reg                busy,
    output reg                done,
    output reg  signed [47:0] product
);

  reg [47:0] accumulator;
  reg [47:0] multiplicand;
  reg [23:0] multiplier;
  reg [4:0] bit_count;
  reg negative_result;

  wire [23:0] magnitude_a =
      operand_a[23] ? (~operand_a[23:0] + 1'b1) : operand_a[23:0];
  wire [23:0] magnitude_b =
      operand_b[23] ? (~operand_b[23:0] + 1'b1) : operand_b[23:0];
  wire [47:0] next_accumulator =
      multiplier[0] ? accumulator + multiplicand : accumulator;

  always @(posedge clk) begin
    if (!rst_n) begin
      accumulator <= 48'b0;
      multiplicand <= 48'b0;
      multiplier <= 24'b0;
      bit_count <= 5'b0;
      negative_result <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      product <= 48'sd0;
    end else begin
      done <= 1'b0;
      if (start && !busy) begin
        accumulator <= 48'b0;
        multiplicand <= {24'b0, magnitude_a};
        multiplier <= magnitude_b;
        bit_count <= 5'b0;
        negative_result <= operand_a[23] ^ operand_b[23];
        busy <= 1'b1;
      end else if (busy) begin
        accumulator <= next_accumulator;
        multiplicand <= multiplicand << 1;
        multiplier <= multiplier >> 1;
        if (bit_count == 5'd23) begin
          product <= negative_result ? -$signed(next_accumulator) :
              $signed(next_accumulator);
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          bit_count <= bit_count + 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
