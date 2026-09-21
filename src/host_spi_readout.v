/*
 * Copyright (c) 2026 Tisham Dhar
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module host_spi_readout (
    input  wire               clk,
    input  wire               rst_n,
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
    input  wire [31:0]        measurement_sequence,
    input  wire [31:0]        voltage_rms,
    input  wire [31:0]        current_rms,
    input  wire signed [63:0] active_power,
    input  wire signed [63:0] active_energy,
    input  wire [23:0]        adc_status,
    output reg  signed [23:0] voltage_offset,
    output reg  signed [23:0] current_offset
);

  reg host_cs_meta;
  reg host_cs_sync;
  reg host_sclk_meta;
  reg host_sclk_sync;
  reg host_sclk_delayed;
  reg host_mosi_meta;
  reg host_mosi_sync;
  reg [7:0] address_shift;
  reg [6:0] bit_count;
  reg [31:0] write_shift;
  reg [63:0] transmit_shift;
  reg transaction_write;

  wire sclk_rising = host_sclk_sync && !host_sclk_delayed;
  wire [7:0] received_address = {address_shift[6:0], host_mosi_sync};
  wire [31:0] received_write_data = {write_shift[30:0], host_mosi_sync};

  assign host_miso = transmit_shift[63];

  function [63:0] read_register;
    input [6:0] address;
    begin
      case (address)
        7'h00: read_register = 64'h4354_5654_4453_5031;
        7'h01: read_register = {32'b0, snapshot_sequence};
        7'h02: read_register = {40'b0, adc_status};
        7'h10: read_register = sum_active_power;
        7'h11: read_register = sum_voltage_sq;
        7'h12: read_register = sum_current_sq;
        7'h13: read_register = sum_voltage;
        7'h14: read_register = sum_current;
        7'h20: read_register = {32'b0, measurement_sequence};
        7'h21: read_register = {32'b0, voltage_rms};
        7'h22: read_register = {32'b0, current_rms};
        7'h23: read_register = active_power;
        7'h24: read_register = active_energy;
        7'h40: read_register = {{40{voltage_offset[23]}}, voltage_offset};
        7'h41: read_register = {{40{current_offset[23]}}, current_offset};
        default: read_register = 64'b0;
      endcase
    end
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      host_cs_meta <= 1'b1;
      host_cs_sync <= 1'b1;
      host_sclk_meta <= 1'b0;
      host_sclk_sync <= 1'b0;
      host_sclk_delayed <= 1'b0;
      host_mosi_meta <= 1'b0;
      host_mosi_sync <= 1'b0;
      address_shift <= 8'b0;
      bit_count <= 7'd0;
      write_shift <= 32'b0;
      transmit_shift <= 64'b0;
      transaction_write <= 1'b0;
      voltage_offset <= 24'sd0;
      current_offset <= 24'sd0;
    end else begin
      host_cs_meta <= host_cs_n;
      host_cs_sync <= host_cs_meta;
      host_sclk_meta <= host_sclk;
      host_sclk_sync <= host_sclk_meta;
      host_sclk_delayed <= host_sclk_sync;
      host_mosi_meta <= host_mosi;
      host_mosi_sync <= host_mosi_meta;
      if (host_cs_sync) begin
        address_shift <= 8'b0;
        bit_count <= 7'd0;
        write_shift <= 32'b0;
        transmit_shift <= 64'b0;
        transaction_write <= 1'b0;
      end else if (sclk_rising) begin
        if (bit_count < 7) begin
          address_shift <= received_address;
          bit_count <= bit_count + 1'b1;
        end else if (bit_count == 7) begin
          address_shift <= received_address;
          transaction_write <= received_address[7];
          if (!received_address[7])
            transmit_shift <= read_register(received_address[6:0]);
          bit_count <= bit_count + 1'b1;
        end else if (transaction_write && bit_count < 40) begin
          write_shift <= received_write_data;
          bit_count <= bit_count + 1'b1;
          if (bit_count == 39) begin
            case (address_shift[6:0])
              7'h40: voltage_offset <= received_write_data[23:0];
              7'h41: current_offset <= received_write_data[23:0];
              default: begin end
            endcase
          end
        end else if (!transaction_write) begin
          transmit_shift <= {transmit_shift[62:0], 1'b0};
          bit_count <= bit_count + 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
