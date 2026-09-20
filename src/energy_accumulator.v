/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module energy_accumulator #(
    parameter integer WINDOW_LOG2 = 8
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire signed [23:0] voltage_sample,
    input  wire signed [23:0] current_sample,
    output reg                snapshot_valid,
    output reg  [31:0]        snapshot_sequence,
    output reg  signed [63:0] sum_active_power,
    output reg  [63:0]        sum_voltage_sq,
    output reg  [63:0]        sum_current_sq,
    output reg  signed [63:0] sum_voltage,
    output reg  signed [63:0] sum_current
);

  reg [WINDOW_LOG2-1:0] sample_count;
  reg [1:0] operation;
  reg busy;
  reg signed [23:0] voltage_latched;
  reg signed [23:0] current_latched;
  reg signed [47:0] active_product;
  reg [47:0] voltage_square;
  reg signed [63:0] active_accumulator;
  reg [63:0] voltage_sq_accumulator;
  reg [63:0] current_sq_accumulator;
  reg signed [63:0] voltage_accumulator;
  reg signed [63:0] current_accumulator;

  wire signed [23:0] multiplier_a =
      (operation == 2'd0) ? voltage_latched :
      (operation == 2'd1) ? voltage_latched : current_latched;
  wire signed [23:0] multiplier_b =
      (operation == 2'd0) ? current_latched :
      (operation == 2'd1) ? voltage_latched : current_latched;
  wire signed [47:0] multiplier_result = multiplier_a * multiplier_b;
  wire signed [63:0] voltage_extended =
      {{40{voltage_latched[23]}}, voltage_latched};
  wire signed [63:0] current_extended =
      {{40{current_latched[23]}}, current_latched};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_count <= {WINDOW_LOG2{1'b0}};
      operation <= 2'd0;
      busy <= 1'b0;
      voltage_latched <= 24'sd0;
      current_latched <= 24'sd0;
      active_product <= 48'sd0;
      voltage_square <= 48'd0;
      active_accumulator <= 64'sd0;
      voltage_sq_accumulator <= 64'd0;
      current_sq_accumulator <= 64'd0;
      voltage_accumulator <= 64'sd0;
      current_accumulator <= 64'sd0;
      snapshot_valid <= 1'b0;
      snapshot_sequence <= 32'd0;
      sum_active_power <= 64'sd0;
      sum_voltage_sq <= 64'd0;
      sum_current_sq <= 64'd0;
      sum_voltage <= 64'sd0;
      sum_current <= 64'sd0;
    end else begin
      snapshot_valid <= 1'b0;
      if (!busy && sample_valid) begin
        voltage_latched <= voltage_sample;
        current_latched <= current_sample;
        operation <= 2'd0;
        busy <= 1'b1;
      end else if (busy) begin
        case (operation)
          2'd0: begin
            active_product <= multiplier_result;
            operation <= 2'd1;
          end
          2'd1: begin
            voltage_square <= multiplier_result;
            operation <= 2'd2;
          end
          default: begin
            busy <= 1'b0;
            if (&sample_count) begin
              sum_active_power <= active_accumulator + active_product;
              sum_voltage_sq <= voltage_sq_accumulator + voltage_square;
              sum_current_sq <= current_sq_accumulator + multiplier_result;
              sum_voltage <= voltage_accumulator + voltage_extended;
              sum_current <= current_accumulator + current_extended;
              snapshot_sequence <= snapshot_sequence + 1'b1;
              snapshot_valid <= 1'b1;
              sample_count <= {WINDOW_LOG2{1'b0}};
              active_accumulator <= 64'sd0;
              voltage_sq_accumulator <= 64'd0;
              current_sq_accumulator <= 64'd0;
              voltage_accumulator <= 64'sd0;
              current_accumulator <= 64'sd0;
            end else begin
              sample_count <= sample_count + 1'b1;
              active_accumulator <= active_accumulator + active_product;
              voltage_sq_accumulator <= voltage_sq_accumulator + voltage_square;
              current_sq_accumulator <= current_sq_accumulator + multiplier_result;
              voltage_accumulator <= voltage_accumulator + voltage_extended;
              current_accumulator <= current_accumulator + current_extended;
            end
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
