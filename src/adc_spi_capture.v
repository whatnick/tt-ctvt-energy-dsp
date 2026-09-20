/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module adc_spi_capture #(
    parameter integer CLK_DIV = 4
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               adc_drdy_n,
    input  wire               adc_dout,
    output reg                adc_cs_n,
    output reg                adc_sclk,
    output wire               adc_din,
    output reg                sample_valid,
    output reg  [23:0]        status_word,
    output reg  signed [23:0] voltage_sample,
    output reg  signed [23:0] current_sample
);

  localparam integer DIV_WIDTH = $clog2(CLK_DIV);

  reg [DIV_WIDTH-1:0] divider;
  reg [6:0] bit_count;
  reg [71:0] shift_register;
  reg active;
  reg finishing;
  reg armed;

  wire [71:0] shifted_frame = {shift_register[70:0], adc_dout};
  assign adc_din = 1'b0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      adc_cs_n <= 1'b1;
      adc_sclk <= 1'b0;
      sample_valid <= 1'b0;
      status_word <= 24'b0;
      voltage_sample <= 24'sd0;
      current_sample <= 24'sd0;
      divider <= {DIV_WIDTH{1'b0}};
      bit_count <= 7'd0;
      shift_register <= 72'b0;
      active <= 1'b0;
      finishing <= 1'b0;
      armed <= 1'b0;
    end else begin
      sample_valid <= 1'b0;

      if (!active) begin
        adc_sclk <= 1'b0;
        adc_cs_n <= 1'b1;
        divider <= {DIV_WIDTH{1'b0}};
        if (adc_drdy_n)
          armed <= 1'b1;
        if (armed && !adc_drdy_n) begin
          active <= 1'b1;
          armed <= 1'b0;
          adc_cs_n <= 1'b0;
          bit_count <= 7'd0;
          shift_register <= 72'b0;
          finishing <= 1'b0;
        end
      end else if (divider == CLK_DIV - 1) begin
        divider <= {DIV_WIDTH{1'b0}};
        if (!adc_sclk) begin
          adc_sclk <= 1'b1;
          shift_register <= shifted_frame;
          if (bit_count == 7'd71) begin
            status_word <= shifted_frame[71:48];
            voltage_sample <= shifted_frame[47:24];
            current_sample <= shifted_frame[23:0];
            finishing <= 1'b1;
          end else begin
            bit_count <= bit_count + 1'b1;
          end
        end else begin
          adc_sclk <= 1'b0;
          if (finishing) begin
            adc_cs_n <= 1'b1;
            active <= 1'b0;
            finishing <= 1'b0;
            sample_valid <= 1'b1;
          end
        end
      end else begin
        divider <= divider + 1'b1;
      end
    end
  end

endmodule

`default_nettype wire
