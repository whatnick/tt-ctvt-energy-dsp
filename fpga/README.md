# FabricFox build

This build targets the iCE40UP5K FabricFox on the Tiny Tapeout FPGA
Development Kit. It enables Yosys DSP inference even though the serialized
ASIC datapath no longer requires hard multipliers. Keeping `-dsp` prevents
future FPGA-only multipliers from silently consuming LUTs.

```sh
cd fpga
python3 -m pip install -r requirements.txt
make report
```

Override `YOSYS`, `NEXTPNR`, and `ICEPACK` when the YoWASP executable names
are not on `PATH`. The FPGA build retains a conservative 25 MHz timing target;
the Tiny Tapeout GF180 configuration uses a nominal 16.384 MHz clock so the
generated ADS131M02 master clock is frequency-coherent.

The YoWASP Yosys and nextpnr versions are pinned in `requirements.txt`.
Placement seeds are only reproducible for a fixed synthesis and place-and-route
toolchain; update the pins only after rerunning timing and hardware upload
validation.

The wrapper and pin constraints derive from
[`TinyTapeout/tt-fpga-compiler`](https://github.com/TinyTapeout/tt-fpga-compiler/tree/89893f61a7e66c9cc5d3c1e8b0c481bd29642c9d/verilog)
at commit `89893f61a7e66c9cc5d3c1e8b0c481bd29642c9d`, licensed Apache-2.0 by
Tiny Tapeout LTD.

## Upload to FabricFox

The FabricFox controller presents a MicroPython serial port. On Windows it
usually appears as `USB Serial Device (COMn)` with Raspberry Pi VID `2E8A`.
Install the uploader dependency:

```powershell
python -m pip install mpremote==1.27.0
```

Build locally in the pinned Linux environment, or download the
`fabricfox-bitstream` artifact from a successful `fpga` GitHub Actions run.
Then upload and configure it:

```powershell
python scripts\upload_fabricfox.py `
  --port COM5 `
  --bitstream fpga\build\tt_um_whatnick_ctvt_energy_dsp.bin
```

The script:

1. uploads the bitstream as
   `/bitstreams/tt_um_whatnick_ctvt_energy_dsp.bin`;
2. reads it back and verifies its SHA-256 hash;
3. preserves the existing `config.ini` while selecting the CTVT image;
4. configures a 25 MHz project clock;
5. drives `ui_in=0x04`, keeping host `CSn` inactive;
6. leaves all RP2350 bidirectional drivers disabled; and
7. soft-reboots and verifies that the project automatically loads.

The configuration file is deliberately written with LF-only line endings.
The controller's minimal INI parser does not recognize a Windows file
containing doubled carriage returns.

With no PMOD attached, a healthy loaded image reports `uo_out=0x40`.
Repeated `uio_out` reads alternate between `0x21` and `0x61`: ADC `CSn` and
`RESETn` are high, while `CLK_HOST` toggles. These checks validate the FPGA
upload, reset, and clock path but do not validate ADC SPI capture.
