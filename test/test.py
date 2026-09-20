# SPDX-FileCopyrightText: © 2026 Tisham Dhar
# SPDX-License-Identifier: Apache-2.0

import cocotb
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
        await Timer(100, unit="ns")
        dut.ui_in.value = int(dut.ui_in.value) | 0x08
        await Timer(100, unit="ns")

    dut._log.info(
        "Host register 0x%02x ui=0x%02x address=0x%02x count=%d loaded 0x%016x",
        address,
        int(dut.ui_in.value),
        int(dut.user_project.host_readout.address_shift.value),
        int(dut.user_project.host_readout.bit_count.value),
        int(dut.user_project.host_readout.transmit_shift.value),
    )

    result = 0
    for _ in range(64):
        dut.ui_in.value = int(dut.ui_in.value) & ~0x08
        await Timer(100, unit="ns")
        result = (result << 1) | int(dut.host_miso.value)
        dut.ui_in.value = int(dut.ui_in.value) | 0x08
        await Timer(100, unit="ns")

    dut.ui_in.value = int(dut.ui_in.value) | 0x04
    await Timer(1, unit="ns")
    return result


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

    voltage = 1000
    current = -250
    status = 0x050000
    for _ in range(256):
        await send_adc_frame(dut, status, voltage, current)

    await ClockCycles(dut.clk, 4)
    assert ((int(dut.uo_out.value) >> 4) & 1) == 0
    assert await host_read(dut, 0x00) == 0x4354565444535031
    assert await host_read(dut, 0x01) == 1
    assert await host_read(dut, 0x02) == status
    assert await host_read(dut, 0x10) == ((voltage * current * 256) & ((1 << 64) - 1))
    assert await host_read(dut, 0x11) == voltage * voltage * 256
    assert await host_read(dut, 0x12) == current * current * 256
    assert await host_read(dut, 0x13) == voltage * 256
    assert await host_read(dut, 0x14) == ((current * 256) & ((1 << 64) - 1))

    dut.ui_in.value = int(dut.ui_in.value) | 0x20
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = int(dut.ui_in.value) & ~0x20
    await ClockCycles(dut.clk, 1)
    assert ((int(dut.uo_out.value) >> 4) & 1) == 1
