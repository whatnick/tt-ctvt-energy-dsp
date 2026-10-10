/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_whatnick_ctvt_energy_dsp (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  wire adc_cs_n;
  wire adc_sclk;
  wire adc_din;
  wire adc_reset_n;
  wire adc_mclk;
  wire sample_valid;
  wire signed [23:0] voltage_sample;
  wire signed [23:0] current_sample;
  wire [23:0] adc_status;

  adc_spi_capture #(
      .CLK_DIV(4)
  ) adc_capture (
      .clk(clk),
      .rst_n(rst_n),
      .adc_drdy_n(uio_in[4]),
      .adc_dout(uio_in[2]),
      .adc_cs_n(adc_cs_n),
      .adc_sclk(adc_sclk),
      .adc_din(adc_din),
      .adc_reset_n(adc_reset_n),
      .adc_mclk(adc_mclk),
      .sample_valid(sample_valid),
      .status_word(adc_status),
      .voltage_sample(voltage_sample),
      .current_sample(current_sample)
  );

  wire signed [23:0] voltage_offset;
  wire signed [23:0] current_offset;
  wire snapshot_valid;
  wire [31:0] snapshot_sequence;
  wire signed [55:0] sum_active_power;
  wire [55:0] sum_voltage_sq;
  wire [55:0] sum_current_sq;
  wire signed [31:0] sum_voltage;
  wire signed [31:0] sum_current;
  wire signed [23:0] calibrated_voltage;
  wire signed [23:0] calibrated_current;

  energy_accumulator #(
      .WINDOW_LOG2(8)
  ) accumulator (
      .clk(clk),
      .rst_n(rst_n),
      .sample_valid(sample_valid),
      .voltage_sample(voltage_sample),
      .current_sample(current_sample),
      .voltage_offset(voltage_offset),
      .current_offset(current_offset),
      .snapshot_valid(snapshot_valid),
      .snapshot_sequence(snapshot_sequence),
      .sum_active_power(sum_active_power),
      .sum_voltage_sq(sum_voltage_sq),
      .sum_current_sq(sum_current_sq),
      .sum_voltage(sum_voltage),
      .sum_current(sum_current),
      .calibrated_voltage(calibrated_voltage),
      .calibrated_current(calibrated_current)
  );

  wire measurement_valid;
  wire [31:0] measurement_sequence;
  wire [23:0] voltage_rms;
  wire [23:0] current_rms;
  wire signed [55:0] active_power;
  wire signed [63:0] active_energy;

  metering_postprocess #(
      .WINDOW_LOG2(8)
  ) postprocess (
      .clk(clk),
      .rst_n(rst_n),
      .snapshot_valid(snapshot_valid),
      .sum_active_power(sum_active_power),
      .sum_voltage_sq(sum_voltage_sq),
      .sum_current_sq(sum_current_sq),
      .measurement_valid(measurement_valid),
      .measurement_sequence(measurement_sequence),
      .voltage_rms(voltage_rms),
      .current_rms(current_rms),
      .active_power(active_power),
      .active_energy(active_energy)
  );

  wire host_miso;
  host_spi_readout host_readout (
      .clk(clk),
      .rst_n(rst_n),
      .host_cs_n(ui_in[2]),
      .host_sclk(ui_in[3]),
      .host_mosi(ui_in[4]),
      .host_miso(host_miso),
      .snapshot_sequence(snapshot_sequence),
      .sum_active_power(sum_active_power),
      .sum_voltage_sq(sum_voltage_sq),
      .sum_current_sq(sum_current_sq),
      .sum_voltage(sum_voltage),
      .sum_current(sum_current),
      .measurement_sequence(measurement_sequence),
      .voltage_rms(voltage_rms),
      .current_rms(current_rms),
      .active_power(active_power),
      .active_energy(active_energy),
      .adc_status(adc_status),
      .voltage_offset(voltage_offset),
      .current_offset(current_offset)
  );

  reg measurement_pending;
  always @(posedge clk) begin
    if (!rst_n)
      measurement_pending <= 1'b0;
    else if (measurement_valid)
      measurement_pending <= 1'b1;
    else if (ui_in[5])
      measurement_pending <= 1'b0;
  end

  assign uo_out[4:0] = 5'b0;
  assign uo_out[5] = host_miso;
  assign uo_out[6] = ~measurement_pending;
  assign uo_out[7] = sample_valid;

  assign uio_out[0] = adc_cs_n;
  assign uio_out[1] = adc_din;
  assign uio_out[2] = 1'b0;
  assign uio_out[3] = adc_sclk;
  assign uio_out[4] = 1'b0;
  assign uio_out[5] = adc_reset_n;
  assign uio_out[6] = adc_mclk;
  assign uio_out[7] = 1'b0;
  assign uio_oe = 8'b0110_1011;

  wire _unused = &{ena, ui_in[7:6], ui_in[1:0], uio_in[7], 1'b0};

endmodule

`default_nettype wire
