# FabricFox build

This build targets the iCE40UP5K FabricFox on the Tiny Tapeout FPGA
Development Kit. It enables Yosys DSP inference even though the serialized
ASIC datapath no longer requires hard multipliers. Keeping `-dsp` prevents
future FPGA-only multipliers from silently consuming LUTs.

```sh
cd fpga
make report
```

Override `YOSYS`, `NEXTPNR`, and `ICEPACK` when the YoWASP executable names
are not on `PATH`. The FPGA build retains a conservative 25 MHz timing target;
the Tiny Tapeout GF180 configuration uses a nominal 16.384 MHz clock so the
generated ADS131M02 master clock is frequency-coherent.

The wrapper and pin constraints derive from
[`TinyTapeout/tt-fpga-compiler`](https://github.com/TinyTapeout/tt-fpga-compiler/tree/89893f61a7e66c9cc5d3c1e8b0c481bd29642c9d/verilog)
at commit `89893f61a7e66c9cc5d3c1e8b0c481bd29642c9d`, licensed Apache-2.0 by
Tiny Tapeout LTD.
