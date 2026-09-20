/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module host_spi_readout (
    input  wire               host_cs_n,
    input  wire               host_sclk,
    input  wire               host_mosi,
    output wire               host_miso,
    input  wire [31:0]        snapshot_sequence,
    input  wire signed [63:0] sum_active_power,
    input  wire [63:0]        sum_voltage_sq,
    input  wire [63:0]        sum_current_sq,
    input  wire signed [63:0] sum_voltage,
    input  wire signed [63:0] sum_current,
    input  wire [23:0]        adc_status
);

  reg [7:0] address_shift;
  reg [6:0] bit_count;
  reg [63:0] transmit_shift;

  assign host_miso = transmit_shift[63];

  function [63:0] read_register;
    input [7:0] address;
    begin
      case (address)
        8'h00: read_register = 64'h4354_5654_4453_5031;
        8'h01: read_register = {32'b0, snapshot_sequence};
        8'h02: read_register = {40'b0, adc_status};
        8'h10: read_register = sum_active_power;
        8'h11: read_register = sum_voltage_sq;
        8'h12: read_register = sum_current_sq;
        8'h13: read_register = sum_voltage;
        8'h14: read_register = sum_current;
        default: read_register = 64'b0;
      endcase
    end
  endfunction

  always @(posedge host_sclk or posedge host_cs_n) begin
    if (host_cs_n) begin
      address_shift <= 8'b0;
      bit_count <= 7'd0;
      transmit_shift <= 64'b0;
    end else if (bit_count < 7) begin
      address_shift <= {address_shift[6:0], host_mosi};
      bit_count <= bit_count + 1'b1;
    end else if (bit_count == 7) begin
      address_shift <= {address_shift[6:0], host_mosi};
      transmit_shift <= read_register({address_shift[6:0], host_mosi});
      bit_count <= bit_count + 1'b1;
    end else begin
      transmit_shift <= {transmit_shift[62:0], 1'b0};
      bit_count <= bit_count + 1'b1;
    end
  end

endmodule

`default_nettype wire
