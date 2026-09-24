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
are not on `PATH`. The default timing target is the 25 MHz clock declared in
`info.yaml`.

The wrapper and pin constraints derive from
[`TinyTapeout/tt-fpga-compiler`](https://github.com/TinyTapeout/tt-fpga-compiler/tree/89893f61a7e66c9cc5d3c1e8b0c481bd29642c9d/verilog)
at commit `89893f61a7e66c9cc5d3c1e8b0c481bd29642c9d`, licensed Apache-2.0 by
Tiny Tapeout LTD.
