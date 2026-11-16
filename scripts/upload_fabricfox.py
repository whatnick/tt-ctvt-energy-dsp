#!/usr/bin/env python3
"""Upload and configure the CTVT FabricFox bitstream."""

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


PROJECT = "tt_um_whatnick_ctvt_energy_dsp"


def run_mpremote(port: str, *args: str) -> None:
    subprocess.run(
        [sys.executable, "-m", "mpremote", "connect", port, *args],
        check=True,
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def set_ini_value(text: str, section: str, key: str, value: str) -> str:
    lines = text.replace("\r\n", "\n").replace("\r", "\n").splitlines()
    header = f"[{section}]"

    try:
        section_start = lines.index(header)
    except ValueError:
        if lines and lines[-1]:
            lines.append("")
        lines.extend([header, f"{key} = {value}"])
        return "\n".join(lines) + "\n"

    section_end = len(lines)
    for index in range(section_start + 1, len(lines)):
        if lines[index].startswith("[") and lines[index].endswith("]"):
            section_end = index
            break

    for index in range(section_start + 1, section_end):
        candidate = lines[index].strip()
        if candidate.startswith("#") or "=" not in candidate:
            continue
        if candidate.split("=", 1)[0].strip() == key:
            lines[index] = f"{key} = {value}"
            return "\n".join(lines) + "\n"

    lines.insert(section_end, f"{key} = {value}")
    return "\n".join(lines) + "\n"


def configure_text(text: str, project: str, clock_hz: int) -> str:
    text = set_ini_value(text, "DEFAULT", "project", project)
    settings = {
        "clock_frequency": str(clock_hz),
        "mode": "ASIC_RP_CONTROL",
        "start_in_reset": "no",
        "ui_in": "4",
        "uio_oe_pico": "0",
        "uio_in": "0",
    }
    for key, value in settings.items():
        text = set_ini_value(text, project, key, value)
    return text


def verify_boot(port: str, project: str, clock_hz: int) -> str:
    import serial

    with serial.Serial(port, 115200, timeout=0.2) as console:
        console.write(b"\x03\x04")
        deadline = time.time() + 12
        output = bytearray()
        while time.time() < deadline:
            output.extend(console.read(4096))

    text = output.decode("utf-8", "replace")
    required = [
        f"Enable design {project}",
        f"auto-clocking @ {clock_hz}",
        f"FPGA project 'FPGA:{project}'",
    ]
    missing = [marker for marker in required if marker not in text]
    if "Traceback" in text or missing:
        raise RuntimeError(
            f"FabricFox boot verification failed; missing={missing}\n{text}"
        )
    return text


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    default_port = "COM5" if os.name == "nt" else "/dev/ttyACM0"
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default=default_port)
    parser.add_argument(
        "--bitstream",
        type=Path,
        default=root / "fpga" / "build" / f"{PROJECT}.bin",
    )
    parser.add_argument("--project", default=PROJECT)
    parser.add_argument("--clock-hz", type=int, default=25_000_000)
    args = parser.parse_args()

    bitstream = args.bitstream.resolve()
    if not bitstream.is_file():
        parser.error(f"bitstream does not exist: {bitstream}")

    remote_bitstream = f":/bitstreams/{args.project}.bin"
    with tempfile.TemporaryDirectory(prefix="ctvt-fabricfox-") as temporary:
        temporary_path = Path(temporary)
        readback = temporary_path / bitstream.name
        config = temporary_path / "config.ini"

        run_mpremote(args.port, "fs", "cp", str(bitstream), remote_bitstream)
        run_mpremote(args.port, "fs", "cp", remote_bitstream, str(readback))

        local_hash = sha256(bitstream)
        readback_hash = sha256(readback)
        if local_hash != readback_hash:
            raise RuntimeError(
                f"bitstream readback mismatch: {local_hash} != {readback_hash}"
            )

        run_mpremote(args.port, "fs", "cp", ":/config.ini", str(config))
        configured = configure_text(
            config.read_text(encoding="utf-8"),
            args.project,
            args.clock_hz,
        )
        config.write_text(configured, encoding="utf-8", newline="\n")
        run_mpremote(args.port, "fs", "cp", str(config), ":/config.ini")

    boot_output = verify_boot(args.port, args.project, args.clock_hz)
    print(f"Uploaded {bitstream}")
    print(f"SHA-256 {local_hash}")
    print(
        f"Verified {args.project} auto-loads on {args.port} at "
        f"{args.clock_hz} Hz"
    )
    print(boot_output)


if __name__ == "__main__":
    main()
