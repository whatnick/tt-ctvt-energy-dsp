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
  wire sample_valid;
  wire signed [23:0] voltage_sample;
  wire signed [23:0] current_sample;
  wire [23:0] adc_status;

  adc_spi_capture #(
      .CLK_DIV(4)
  ) adc_capture (
      .clk(clk),
      .rst_n(rst_n),
      .adc_drdy_n(ui_in[1]),
      .adc_dout(ui_in[0]),
      .adc_cs_n(adc_cs_n),
      .adc_sclk(adc_sclk),
      .adc_din(adc_din),
      .sample_valid(sample_valid),
      .status_word(adc_status),
      .voltage_sample(voltage_sample),
      .current_sample(current_sample)
  );

  wire snapshot_valid;
  wire [31:0] snapshot_sequence;
  wire signed [63:0] sum_active_power;
  wire [63:0] sum_voltage_sq;
  wire [63:0] sum_current_sq;
  wire signed [63:0] sum_voltage;
  wire signed [63:0] sum_current;

  energy_accumulator #(
      .WINDOW_LOG2(8)
  ) accumulator (
      .clk(clk),
      .rst_n(rst_n),
      .sample_valid(sample_valid),
      .voltage_sample(voltage_sample),
      .current_sample(current_sample),
      .snapshot_valid(snapshot_valid),
      .snapshot_sequence(snapshot_sequence),
      .sum_active_power(sum_active_power),
      .sum_voltage_sq(sum_voltage_sq),
      .sum_current_sq(sum_current_sq),
      .sum_voltage(sum_voltage),
      .sum_current(sum_current)
  );

  wire measurement_valid;
  wire [31:0] measurement_sequence;
  wire [31:0] voltage_rms;
  wire [31:0] current_rms;
  wire signed [63:0] active_power;
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
      .adc_status(adc_status)
  );

  reg measurement_pending;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      measurement_pending <= 1'b0;
    else if (measurement_valid)
      measurement_pending <= 1'b1;
    else if (ui_in[5])
      measurement_pending <= 1'b0;
  end

  assign uo_out[0] = adc_cs_n;
  assign uo_out[1] = adc_sclk;
  assign uo_out[2] = adc_din;
  assign uo_out[3] = host_miso;
  assign uo_out[4] = ~measurement_pending;
  assign uo_out[5] = sample_valid;
  assign uo_out[6] = voltage_sample[23];
  assign uo_out[7] = current_sample[23];

  assign uio_out = 8'b0;
  assign uio_oe = 8'b0;

  wire _unused = &{ena, ui_in[7:6], uio_in, 1'b0};

endmodule

`default_nettype wire
