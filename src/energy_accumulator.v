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
    input  wire signed [23:0] voltage_offset,
    input  wire signed [23:0] current_offset,
    output reg                snapshot_valid,
    output reg  [31:0]        snapshot_sequence,
    output reg  signed [55:0] sum_active_power,
    output reg  [55:0]        sum_voltage_sq,
    output reg  [55:0]        sum_current_sq,
    output reg  signed [31:0] sum_voltage,
    output reg  signed [31:0] sum_current,
    output reg  signed [23:0] calibrated_voltage,
    output reg  signed [23:0] calibrated_current
);

  localparam [3:0] IDLE = 4'd0;
  localparam [3:0] CALIBRATE_VOLTAGE = 4'd1;
  localparam [3:0] CALIBRATE_CURRENT = 4'd2;
  localparam [3:0] START_ACTIVE = 4'd3;
  localparam [3:0] WAIT_ACTIVE = 4'd4;
  localparam [3:0] ADD_ACTIVE = 4'd5;
  localparam [3:0] ADD_VOLTAGE = 4'd6;
  localparam [3:0] ADD_CURRENT = 4'd7;
  localparam [3:0] START_VOLTAGE_SQ = 4'd8;
  localparam [3:0] WAIT_VOLTAGE_SQ = 4'd9;
  localparam [3:0] ADD_VOLTAGE_SQ = 4'd10;
  localparam [3:0] START_CURRENT_SQ = 4'd11;
  localparam [3:0] WAIT_CURRENT_SQ = 4'd12;
  localparam [3:0] ADD_CURRENT_SQ = 4'd13;

  reg [3:0] state;
  reg [WINDOW_LOG2-1:0] sample_count;
  reg signed [55:0] active_accumulator;
  reg [55:0] voltage_sq_accumulator;
  reg [55:0] current_sq_accumulator;
  reg signed [31:0] voltage_accumulator;
  reg signed [31:0] current_accumulator;
  wire multiplier_start =
      (state == START_ACTIVE) ||
      (state == START_VOLTAGE_SQ) ||
      (state == START_CURRENT_SQ);

  wire signed [23:0] calibration_sample =
      (state == CALIBRATE_VOLTAGE) ? voltage_sample : current_sample;
  wire signed [23:0] calibration_offset =
      (state == CALIBRATE_VOLTAGE) ? voltage_offset : current_offset;
  wire signed [24:0] calibration_difference =
      {calibration_sample[23], calibration_sample} -
      {calibration_offset[23], calibration_offset};
  wire signed [23:0] calibration_result =
      (calibration_difference > 25'sd8388607) ? 24'sh7fffff :
      (calibration_difference < -25'sd8388608) ? 24'sh800000 :
      calibration_difference[23:0];

  wire signed [23:0] multiplier_a =
      (state == START_ACTIVE) ? calibrated_voltage :
      (state == START_VOLTAGE_SQ) ? calibrated_voltage :
      calibrated_current;
  wire signed [23:0] multiplier_b =
      (state == START_ACTIVE) ? calibrated_current :
      (state == START_VOLTAGE_SQ) ? calibrated_voltage :
      calibrated_current;
  wire multiplier_busy;
  wire multiplier_done;
  wire signed [47:0] multiplier_product;

  serial_multiplier multiplier (
      .clk(clk),
      .rst_n(rst_n),
      .start(multiplier_start),
      .operand_a(multiplier_a),
      .operand_b(multiplier_b),
      .busy(multiplier_busy),
      .done(multiplier_done),
      .product(multiplier_product)
  );

  reg [55:0] adder_a;
  reg [55:0] adder_b;
  wire [55:0] adder_result = adder_a + adder_b;

  always @(*) begin
    adder_a = 56'b0;
    adder_b = 56'b0;
    case (state)
      ADD_ACTIVE: begin
        adder_a = active_accumulator;
        adder_b = {{8{multiplier_product[47]}}, multiplier_product};
      end
      ADD_VOLTAGE: begin
        adder_a = {{24{voltage_accumulator[31]}}, voltage_accumulator};
        adder_b = {{32{calibrated_voltage[23]}}, calibrated_voltage};
      end
      ADD_CURRENT: begin
        adder_a = {{24{current_accumulator[31]}}, current_accumulator};
        adder_b = {{32{calibrated_current[23]}}, calibrated_current};
      end
      ADD_VOLTAGE_SQ: begin
        adder_a = voltage_sq_accumulator;
        adder_b = {{8{1'b0}}, multiplier_product};
      end
      ADD_CURRENT_SQ: begin
        adder_a = current_sq_accumulator;
        adder_b = {{8{1'b0}}, multiplier_product};
      end
      default: begin
        adder_a = 56'b0;
        adder_b = 56'b0;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      sample_count <= {WINDOW_LOG2{1'b0}};
      active_accumulator <= 56'sd0;
      voltage_sq_accumulator <= 56'd0;
      current_sq_accumulator <= 56'd0;
      voltage_accumulator <= 32'sd0;
      current_accumulator <= 32'sd0;
      snapshot_valid <= 1'b0;
      snapshot_sequence <= 32'd0;
      sum_active_power <= 56'sd0;
      sum_voltage_sq <= 56'd0;
      sum_current_sq <= 56'd0;
      sum_voltage <= 32'sd0;
      sum_current <= 32'sd0;
      calibrated_voltage <= 24'sd0;
      calibrated_current <= 24'sd0;
    end else begin
      snapshot_valid <= 1'b0;
      case (state)
        IDLE: begin
          if (sample_valid)
            state <= CALIBRATE_VOLTAGE;
        end
        CALIBRATE_VOLTAGE: begin
          calibrated_voltage <= calibration_result;
          state <= CALIBRATE_CURRENT;
        end
        CALIBRATE_CURRENT: begin
          calibrated_current <= calibration_result;
          state <= START_ACTIVE;
        end
        START_ACTIVE: begin
          state <= WAIT_ACTIVE;
        end
        WAIT_ACTIVE: begin
          if (multiplier_done)
            state <= ADD_ACTIVE;
        end
        ADD_ACTIVE: begin
          active_accumulator <= adder_result;
          state <= ADD_VOLTAGE;
        end
        ADD_VOLTAGE: begin
          voltage_accumulator <= adder_result[31:0];
          state <= ADD_CURRENT;
        end
        ADD_CURRENT: begin
          current_accumulator <= adder_result[31:0];
          state <= START_VOLTAGE_SQ;
        end
        START_VOLTAGE_SQ: begin
          state <= WAIT_VOLTAGE_SQ;
        end
        WAIT_VOLTAGE_SQ: begin
          if (multiplier_done)
            state <= ADD_VOLTAGE_SQ;
        end
        ADD_VOLTAGE_SQ: begin
          voltage_sq_accumulator <= adder_result;
          state <= START_CURRENT_SQ;
        end
        START_CURRENT_SQ: begin
          state <= WAIT_CURRENT_SQ;
        end
        WAIT_CURRENT_SQ: begin
          if (multiplier_done)
            state <= ADD_CURRENT_SQ;
        end
        default: begin
          if (&sample_count) begin
            sum_active_power <= active_accumulator;
            sum_voltage_sq <= voltage_sq_accumulator;
            sum_current_sq <= adder_result;
            sum_voltage <= voltage_accumulator;
            sum_current <= current_accumulator;
            snapshot_sequence <= snapshot_sequence + 1'b1;
            snapshot_valid <= 1'b1;
            sample_count <= {WINDOW_LOG2{1'b0}};
            active_accumulator <= 56'sd0;
            voltage_sq_accumulator <= 56'd0;
            current_sq_accumulator <= 56'd0;
            voltage_accumulator <= 32'sd0;
            current_accumulator <= 32'sd0;
          end else begin
            current_sq_accumulator <= adder_result;
            sample_count <= sample_count + 1'b1;
          end
          state <= IDLE;
        end
      endcase
    end
  end

  wire _unused = &{multiplier_busy, 1'b0};

endmodule

`default_nettype wire
