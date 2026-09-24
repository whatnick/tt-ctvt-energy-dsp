/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module metering_postprocess #(
    parameter integer WINDOW_LOG2 = 8
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               snapshot_valid,
    input  wire signed [55:0] sum_active_power,
    input  wire [55:0]        sum_voltage_sq,
    input  wire [55:0]        sum_current_sq,
    output reg                measurement_valid,
    output reg  [31:0]        measurement_sequence,
    output reg  [23:0]        voltage_rms,
    output reg  [23:0]        current_rms,
    output reg  signed [55:0] active_power,
    output reg  signed [63:0] active_energy
);

  localparam [1:0] IDLE = 2'd0;
  localparam [1:0] VOLTAGE_ROOT = 2'd1;
  localparam [1:0] CURRENT_START = 2'd2;
  localparam [1:0] CURRENT_ROOT = 2'd3;

  reg [1:0] state;
  reg sqrt_start;
  reg [47:0] sqrt_radicand;
  wire sqrt_busy;
  wire sqrt_done;
  wire [23:0] sqrt_root;

  integer_sqrt sqrt_unit (
      .clk(clk),
      .rst_n(rst_n),
      .start(sqrt_start),
      .radicand(sqrt_radicand),
      .busy(sqrt_busy),
      .done(sqrt_done),
      .root(sqrt_root)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      sqrt_start <= 1'b0;
      sqrt_radicand <= 48'b0;
      measurement_valid <= 1'b0;
      measurement_sequence <= 32'b0;
      voltage_rms <= 24'b0;
      current_rms <= 24'b0;
      active_power <= 56'sd0;
      active_energy <= 64'sd0;
    end else begin
      sqrt_start <= 1'b0;
      measurement_valid <= 1'b0;
      case (state)
        IDLE: begin
          if (snapshot_valid) begin
            active_power <= sum_active_power >>> WINDOW_LOG2;
            active_energy <= active_energy +
                {{8{sum_active_power[55]}}, sum_active_power};
            sqrt_radicand <= sum_voltage_sq >> WINDOW_LOG2;
            sqrt_start <= 1'b1;
            state <= VOLTAGE_ROOT;
          end
        end
        VOLTAGE_ROOT: begin
          if (sqrt_done) begin
            voltage_rms <= sqrt_root;
            state <= CURRENT_START;
          end
        end
        CURRENT_START: begin
          if (!sqrt_busy) begin
            sqrt_radicand <= sum_current_sq >> WINDOW_LOG2;
            sqrt_start <= 1'b1;
            state <= CURRENT_ROOT;
          end
        end
        default: begin
          if (sqrt_done) begin
            current_rms <= sqrt_root;
            measurement_sequence <= measurement_sequence + 1'b1;
            measurement_valid <= 1'b1;
            state <= IDLE;
          end
        end
      endcase
    end
  end

endmodule

`default_nettype wire
