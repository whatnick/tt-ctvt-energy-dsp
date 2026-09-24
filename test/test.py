# SPDX-FileCopyrightText: © 2026 Tisham Dhar
# SPDX-License-Identifier: Apache-2.0

import cocotb
import math
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer


def signed24(value: int) -> int:
    return value & 0xFFFFFF


async def send_adc_frame(dut, status: int, voltage: int, current: int) -> None:
    frame = (
        ((status & 0xFFFFFF) << 48)
        | (signed24(voltage) << 24)
        | signed24(current)
    )

    dut.ui_in.value = int(dut.ui_in.value) | 0x02
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = int(dut.ui_in.value) & ~0x02
    await FallingEdge(dut.adc_cs_n)

    for bit in range(71, -1, -1):
        value = int(dut.ui_in.value)
        value = (value | 0x01) if ((frame >> bit) & 1) else (value & ~0x01)
        dut.ui_in.value = value
        await RisingEdge(dut.adc_sclk)

    await RisingEdge(dut.adc_cs_n)
    dut.ui_in.value = int(dut.ui_in.value) | 0x02
    await ClockCycles(dut.clk, 2)


async def host_read(dut, address: int) -> int:
    value = int(dut.ui_in.value)
    dut.ui_in.value = value & ~0x04
    await Timer(1, unit="ns")

    for bit in range(7, -1, -1):
        value = int(dut.ui_in.value)
        value = (value | 0x10) if ((address >> bit) & 1) else (value & ~0x10)
        dut.ui_in.value = value & ~0x08
        await Timer(250, unit="ns")
        dut.ui_in.value = int(dut.ui_in.value) | 0x08
        await Timer(250, unit="ns")

    result = 0
    for _ in range(64):
        dut.ui_in.value = int(dut.ui_in.value) & ~0x08
        await Timer(250, unit="ns")
        result = (result << 1) | int(dut.host_miso.value)
        dut.ui_in.value = int(dut.ui_in.value) | 0x08
        await Timer(250, unit="ns")

    dut.ui_in.value = int(dut.ui_in.value) | 0x04
    await Timer(250, unit="ns")
    return result


async def host_write(dut, address: int, data: int) -> None:
    dut.ui_in.value = int(dut.ui_in.value) & ~0x04
    await ClockCycles(dut.clk, 4)

    command = 0x80 | (address & 0x7F)
    for bit in range(7, -1, -1):
        value = int(dut.ui_in.value)
        value = (value | 0x10) if ((command >> bit) & 1) else (value & ~0x10)
        dut.ui_in.value = value & ~0x08
        await ClockCycles(dut.clk, 8)
        dut.ui_in.value = int(dut.ui_in.value) | 0x08
        await ClockCycles(dut.clk, 8)

    for bit in range(31, -1, -1):
        value = int(dut.ui_in.value)
        value = (value | 0x10) if ((data >> bit) & 1) else (value & ~0x10)
        dut.ui_in.value = value & ~0x08
        await ClockCycles(dut.clk, 8)
        dut.ui_in.value = int(dut.ui_in.value) | 0x08
        await ClockCycles(dut.clk, 8)

    dut.ui_in.value = int(dut.ui_in.value) | 0x04
    await ClockCycles(dut.clk, 4)


@cocotb.test()
async def test_capture_accumulate_and_readout(dut):
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0x06
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)

    voltage_offset = 10
    current_offset = 5
    await host_write(dut, 0x40, voltage_offset)
    await host_write(dut, 0x41, current_offset)
    assert await host_read(dut, 0x40) == voltage_offset
    assert await host_read(dut, 0x41) == current_offset

    voltage = 1000
    current = -250
    status = 0x050000
    for _ in range(256):
        await send_adc_frame(
            dut, status, voltage + voltage_offset, current + current_offset
        )

    await ClockCycles(dut.clk, 160)
    assert ((int(dut.uo_out.value) >> 4) & 1) == 0
    assert await host_read(dut, 0x00) == 0x4354565444535031
    assert await host_read(dut, 0x01) == 1
    assert await host_read(dut, 0x02) == status
    assert await host_read(dut, 0x10) == ((voltage * current * 256) & ((1 << 64) - 1))
    assert await host_read(dut, 0x11) == voltage * voltage * 256
    assert await host_read(dut, 0x12) == current * current * 256
    assert await host_read(dut, 0x13) == voltage * 256
    assert await host_read(dut, 0x14) == ((current * 256) & ((1 << 64) - 1))
    assert await host_read(dut, 0x20) == 1
    assert await host_read(dut, 0x21) == abs(voltage)
    assert await host_read(dut, 0x22) == abs(current)
    assert await host_read(dut, 0x23) == ((voltage * current) & ((1 << 64) - 1))
    assert await host_read(dut, 0x24) == ((voltage * current * 256) & ((1 << 64) - 1))

    dut.ui_in.value = int(dut.ui_in.value) | 0x20
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = int(dut.ui_in.value) & ~0x20
    await ClockCycles(dut.clk, 1)
    assert ((int(dut.uo_out.value) >> 4) & 1) == 1

    voltage_2 = -300
    current_2 = 400
    for _ in range(256):
        await send_adc_frame(
            dut, status, voltage_2 + voltage_offset, current_2 + current_offset
        )

    await ClockCycles(dut.clk, 160)
    assert await host_read(dut, 0x20) == 2
    assert await host_read(dut, 0x21) == abs(voltage_2)
    assert await host_read(dut, 0x22) == abs(current_2)
    assert await host_read(dut, 0x23) == ((voltage_2 * current_2) & ((1 << 64) - 1))
    expected_energy = (voltage * current + voltage_2 * current_2) * 256
    assert await host_read(dut, 0x24) == (expected_energy & ((1 << 64) - 1))

    active_sum_3 = 0
    voltage_sq_sum_3 = 0
    current_sq_sum_3 = 0
    for index in range(256):
        voltage_3 = 3 if index & 1 else 4
        current_3 = 5 if index & 1 else 12
        active_sum_3 += voltage_3 * current_3
        voltage_sq_sum_3 += voltage_3 * voltage_3
        current_sq_sum_3 += current_3 * current_3
        await send_adc_frame(
            dut, status, voltage_3 + voltage_offset, current_3 + current_offset
        )

    await ClockCycles(dut.clk, 160)
    assert await host_read(dut, 0x20) == 3
    assert await host_read(dut, 0x21) == math.isqrt(voltage_sq_sum_3 // 256)
    assert await host_read(dut, 0x22) == math.isqrt(current_sq_sum_3 // 256)
    assert await host_read(dut, 0x23) == active_sum_3 // 256
    expected_energy += active_sum_3
    assert await host_read(dut, 0x24) == (expected_energy & ((1 << 64) - 1))

    await host_write(dut, 0x40, signed24(-10))
    await host_write(dut, 0x41, signed24(10))
    assert await host_read(dut, 0x40) == ((-10) & ((1 << 64) - 1))
    assert await host_read(dut, 0x41) == 10

    saturated_voltage = (1 << 23) - 1
    saturated_current = -(1 << 23)
    for _ in range(256):
        await send_adc_frame(dut, status, saturated_voltage, saturated_current)

    await ClockCycles(dut.clk, 160)
    saturated_active_sum = saturated_voltage * saturated_current * 256
    assert await host_read(dut, 0x20) == 4
    assert await host_read(dut, 0x13) == saturated_voltage * 256
    assert await host_read(dut, 0x14) == (
        (saturated_current * 256) & ((1 << 64) - 1)
    )
    assert await host_read(dut, 0x21) == saturated_voltage
    assert await host_read(dut, 0x22) == abs(saturated_current)
    assert await host_read(dut, 0x23) == (
        (saturated_voltage * saturated_current) & ((1 << 64) - 1)
    )
    expected_energy += saturated_active_sum
    assert await host_read(dut, 0x24) == (expected_energy & ((1 << 64) - 1))
