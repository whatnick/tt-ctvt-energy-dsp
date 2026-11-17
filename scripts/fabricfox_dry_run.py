#!/usr/bin/env python3
"""Exercise CTVT host SPI and synthetic ADC capture on FabricFox."""

import argparse
import os
import sys
import time


DEVICE_ID = 0x4354565444535031


def remote_test(frames: int) -> str:
    return f"""
import time

FRAMES = {frames}
STATUS = 0x050000
VOLTAGE = 1000
CURRENT = -250
VOLTAGE_OFFSET = 10
CURRENT_OFFSET = 5


def step(count=1):
    for _ in range(count):
        tt.clock_project_once()


def set_ui(mask, enabled):
    value = int(tt.ui_in.value)
    tt.ui_in.value = (value | mask) if enabled else (value & ~mask)


def host_read(address):
    set_ui(0x04, False)
    step(6)
    for bit in range(7, -1, -1):
        set_ui(0x10, (address >> bit) & 1)
        set_ui(0x08, False)
        step(6)
        set_ui(0x08, True)
        step(6)
    result = 0
    for _ in range(64):
        set_ui(0x08, False)
        step(6)
        result = (result << 1) | ((int(tt.uo_out.value) >> 5) & 1)
        set_ui(0x08, True)
        step(6)
    set_ui(0x04, True)
    step(6)
    return result


def host_write(address, data):
    set_ui(0x04, False)
    step(6)
    command = 0x80 | (address & 0x7f)
    for value, width in ((command, 8), (data, 32)):
        for bit in range(width - 1, -1, -1):
            set_ui(0x10, (value >> bit) & 1)
            set_ui(0x08, False)
            step(6)
            set_ui(0x08, True)
            step(6)
    set_ui(0x04, True)
    step(6)


def wait_for(pin, value, limit, name):
    for _ in range(limit):
        if pin.value() == value:
            return
        step()
    raise RuntimeError("timeout waiting for " + name)


def send_adc_frame(status, voltage, current):
    frame = (
        ((status & 0xffffff) << 48)
        | ((voltage & 0xffffff) << 24)
        | (current & 0xffffff)
    )
    drdy.value(1)
    step(2)
    dout.value((frame >> 71) & 1)
    drdy.value(0)
    wait_for(cs, 0, 16, "ADC CSn low")
    for bit in range(71, -1, -1):
        dout.value((frame >> bit) & 1)
        wait_for(sclk, 1, 12, "ADC SCLK rising")
        if bit:
            wait_for(sclk, 0, 12, "ADC SCLK falling")
    wait_for(cs, 1, 12, "ADC CSn high")
    drdy.value(1)
    step(2)


tt.clock_project_stop()
tt.uio_oe_pico.value = 0x14
tt.ui_in.value = 0x04
drdy = tt.pins.pin_uio4
dout = tt.pins.pin_uio2
cs = tt.pins.pin_uio0
sclk = tt.pins.pin_uio3
drdy.value(1)
dout.value(0)

try:
    tt.reset_project(True)
    step(10)
    tt.reset_project(False)
    step(4200)

    assert host_read(0x00) == {DEVICE_ID}
    assert host_read(0x03) == 0
    assert host_read(0x04) == 0
    assert host_read(0x05) & 0x1

    host_write(0x40, VOLTAGE_OFFSET)
    host_write(0x41, CURRENT_OFFSET)
    assert host_read(0x40) == VOLTAGE_OFFSET
    assert host_read(0x41) == CURRENT_OFFSET

    started = time.ticks_ms()
    for index in range(FRAMES):
        send_adc_frame(
            STATUS,
            VOLTAGE + VOLTAGE_OFFSET,
            CURRENT + CURRENT_OFFSET,
        )
        if FRAMES == 256 and (index + 1) % 64 == 0:
            print("Injected", index + 1, "frames")
    step(200)
    elapsed_ms = time.ticks_diff(time.ticks_ms(), started)

    actual = {{
        "device_id": host_read(0x00),
        "snapshot_sequence": host_read(0x01),
        "adc_status": host_read(0x02),
        "adc_frame_count": host_read(0x03),
        "adc_overrun_count": host_read(0x04),
        "adc_diagnostics": host_read(0x05),
    }}
    expected = {{
        "device_id": {DEVICE_ID},
        "snapshot_sequence": 1 if FRAMES == 256 else 0,
        "adc_status": STATUS,
        "adc_frame_count": FRAMES,
        "adc_overrun_count": 0,
        "adc_diagnostics": 0xb,
    }}

    if FRAMES == 256:
        actual.update({{
            "sum_active_power": host_read(0x10),
            "sum_voltage_sq": host_read(0x11),
            "sum_current_sq": host_read(0x12),
            "sum_voltage": host_read(0x13),
            "sum_current": host_read(0x14),
            "measurement_sequence": host_read(0x20),
            "voltage_rms": host_read(0x21),
            "current_rms": host_read(0x22),
            "active_power": host_read(0x23),
            "active_energy": host_read(0x24),
        }})
        expected.update({{
            "sum_active_power": (-64000000) & 0xffffffffffffffff,
            "sum_voltage_sq": 256000000,
            "sum_current_sq": 16000000,
            "sum_voltage": 256000,
            "sum_current": (-64000) & 0xffffffffffffffff,
            "measurement_sequence": 1,
            "voltage_rms": 1000,
            "current_rms": 250,
            "active_power": (-250000) & 0xffffffffffffffff,
            "active_energy": (-64000000) & 0xffffffffffffffff,
        }})

    assert actual == expected, (actual, expected)
    assert ((int(tt.uo_out.value) >> 6) & 1) == (0 if FRAMES == 256 else 1)
    set_ui(0x20, True)
    step(2)
    set_ui(0x20, False)
    step(2)
    assert ((int(tt.uo_out.value) >> 6) & 1) == 1

    print("CTVT_DRY_RUN_RESULTS", actual)
    print("CTVT_DRY_RUN_MS", elapsed_ms)
    print("CTVT_DRY_RUN_PASS")
finally:
    drdy.value(1)
    dout.value(0)
    tt.uio_oe_pico.value = 0
    tt.ui_in.value = 0x04
    tt.clock_project_PWM(25000000)
"""


def run_remote(port: str, code: str, timeout: float) -> str:
    import serial

    with serial.Serial(port, 115200, timeout=0.2) as console:
        console.write(b"\x03")
        time.sleep(0.1)
        console.reset_input_buffer()
        console.write(("exec(" + repr(code) + ")\r\n").encode())

        output = bytearray()
        deadline = time.time() + timeout
        while time.time() < deadline:
            output.extend(console.read(4096))
            text = output.decode("utf-8", "replace")
            lines = [line.strip() for line in text.splitlines()]
            if "CTVT_DRY_RUN_PASS" in lines and text.rstrip().endswith(">>>"):
                return text
            if "Traceback (most recent call last)" in text and text.rstrip().endswith(
                ">>>"
            ):
                raise RuntimeError(text)

    raise TimeoutError(
        f"FabricFox dry run did not finish within {timeout:.0f} seconds\n"
        + output.decode("utf-8", "replace")
    )


def main() -> None:
    default_port = "COM5" if os.name == "nt" else "/dev/ttyACM0"
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default=default_port)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--quick",
        action="store_true",
        help="inject one frame instead of validating a full metrology window",
    )
    mode.add_argument(
        "--full",
        action="store_true",
        help="validate the full 256-frame metrology window (default)",
    )
    args = parser.parse_args()

    frames = 1 if args.quick else 256
    timeout = 60 if args.quick else 300
    try:
        output = run_remote(args.port, remote_test(frames), timeout)
    except (OSError, RuntimeError, TimeoutError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error

    print(output)
    print(
        f"Verified CTVT FabricFox {'single-frame path' if args.quick else '256-frame metrology window'} "
        f"on {args.port}"
    )


if __name__ == "__main__":
    main()
