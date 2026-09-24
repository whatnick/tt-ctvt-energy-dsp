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
    input  wire signed [55:0] sum_active_power,
    input  wire [55:0]        sum_voltage_sq,
    input  wire [55:0]        sum_current_sq,
    input  wire signed [31:0] sum_voltage,
    input  wire signed [31:0] sum_current,
    input  wire [31:0]        measurement_sequence,
    input  wire [23:0]        voltage_rms,
    input  wire [23:0]        current_rms,
    input  wire signed [55:0] active_power,
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
  reg [7:0] transmit_byte;
  reg [2:0] transmit_byte_index;
  reg transaction_write;

  wire sclk_rising = host_sclk_sync && !host_sclk_delayed;
  wire [7:0] received_address = {address_shift[6:0], host_mosi_sync};
  wire [31:0] received_write_data = {write_shift[30:0], host_mosi_sync};

  wire [63:0] extended_sum_active_power =
      {{8{sum_active_power[55]}}, sum_active_power};
  wire [63:0] extended_sum_voltage_sq = {8'b0, sum_voltage_sq};
  wire [63:0] extended_sum_current_sq = {8'b0, sum_current_sq};
  wire [63:0] extended_sum_voltage =
      {{32{sum_voltage[31]}}, sum_voltage};
  wire [63:0] extended_sum_current =
      {{32{sum_current[31]}}, sum_current};
  wire [63:0] extended_active_power =
      {{8{active_power[55]}}, active_power};

  assign host_miso = transmit_byte[7];

  function [7:0] select_byte;
    input [63:0] value;
    input [2:0] byte_index;
    begin
      case (byte_index)
        3'd7: select_byte = value[63:56];
        3'd6: select_byte = value[55:48];
        3'd5: select_byte = value[47:40];
        3'd4: select_byte = value[39:32];
        3'd3: select_byte = value[31:24];
        3'd2: select_byte = value[23:16];
        3'd1: select_byte = value[15:8];
        default: select_byte = value[7:0];
      endcase
    end
  endfunction

  function [7:0] read_register_byte;
    input [6:0] address;
    input [2:0] byte_index;
    begin
      case (address)
        7'h00: read_register_byte =
            select_byte(64'h4354_5654_4453_5031, byte_index);
        7'h01: read_register_byte =
            select_byte({32'b0, snapshot_sequence}, byte_index);
        7'h02: read_register_byte =
            select_byte({40'b0, adc_status}, byte_index);
        7'h10: read_register_byte =
            select_byte(extended_sum_active_power, byte_index);
        7'h11: read_register_byte =
            select_byte(extended_sum_voltage_sq, byte_index);
        7'h12: read_register_byte =
            select_byte(extended_sum_current_sq, byte_index);
        7'h13: read_register_byte =
            select_byte(extended_sum_voltage, byte_index);
        7'h14: read_register_byte =
            select_byte(extended_sum_current, byte_index);
        7'h20: read_register_byte =
            select_byte({32'b0, measurement_sequence}, byte_index);
        7'h21: read_register_byte =
            select_byte({40'b0, voltage_rms}, byte_index);
        7'h22: read_register_byte =
            select_byte({40'b0, current_rms}, byte_index);
        7'h23: read_register_byte =
            select_byte(extended_active_power, byte_index);
        7'h24: read_register_byte = select_byte(active_energy, byte_index);
        7'h40: read_register_byte =
            select_byte({{40{voltage_offset[23]}}, voltage_offset}, byte_index);
        7'h41: read_register_byte =
            select_byte({{40{current_offset[23]}}, current_offset}, byte_index);
        default: read_register_byte = 8'b0;
      endcase
    end
  endfunction

  always @(posedge clk) begin
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
      transmit_byte <= 8'b0;
      transmit_byte_index <= 3'd7;
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
        transmit_byte <= 8'b0;
        transmit_byte_index <= 3'd7;
        transaction_write <= 1'b0;
      end else if (sclk_rising) begin
        if (bit_count < 7) begin
          address_shift <= received_address;
          bit_count <= bit_count + 1'b1;
        end else if (bit_count == 7) begin
          address_shift <= received_address;
          transaction_write <= received_address[7];
          if (!received_address[7]) begin
            transmit_byte <=
                read_register_byte(received_address[6:0], 3'd7);
            transmit_byte_index <= 3'd7;
          end
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
          if (bit_count[2:0] == 3'd7) begin
            transmit_byte_index <= transmit_byte_index - 1'b1;
            transmit_byte <= read_register_byte(
                address_shift[6:0], transmit_byte_index - 1'b1);
          end else begin
            transmit_byte <= {transmit_byte[6:0], 1'b0};
          end
          bit_count <= bit_count + 1'b1;
        end
      end
    end
  end

endmodule

`default_nettype wire
