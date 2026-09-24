[![GDS](https://github.com/whatnick/tt-ctvt-energy-dsp/actions/workflows/gds.yaml/badge.svg)](https://github.com/whatnick/tt-ctvt-energy-dsp/actions/workflows/gds.yaml)
[![Tests](https://github.com/whatnick/tt-ctvt-energy-dsp/actions/workflows/test.yaml/badge.svg)](https://github.com/whatnick/tt-ctvt-energy-dsp/actions/workflows/test.yaml)

# CTVT Energy DSP

CTVT Energy DSP is a Tiny Tapeout digital metrology companion for the
[Whatnick CTVT PMOD](https://github.com/whatnick/ctvt-pmod). It controls the
PMOD's ADS131M02 over SPI, captures simultaneous 24-bit voltage/current
samples, and turns the sample stream into coherent measurement snapshots for
a host controller.

The working RTL currently implements:

- ADS131M02-style 72-bit frame capture: status, voltage, and current;
- 256-sample accumulation of `sum(v)`, `sum(i)`, `sum(v*i)`, `sum(v^2)`, and
  `sum(i^2)` using one serialized signed multiplier and one shared adder;
- serial integer square-root processing for voltage/current RMS, window-average
  active power, and cumulative signed active-energy quanta;
- host-writable signed voltage/current ADC-count offsets applied before raw and
  processed accumulation, with register readback;
- atomic result registers with a monotonically increasing sequence number;
- a host SPI readout/calibration interface and level interrupt with explicit
  acknowledge;
- a cocotb test that drives 256 ADC frames and verifies every exported result.

```text
              +---------------- Tiny Tapeout ASIC ----------------+
ADS131M02 --->| SPI capture -> calibration -> serial arithmetic   |
 DRDY/DOUT    |                    |                               |
              |                    +-> moments / energy / events  |
Host SPI <----| snapshot registers |                               |
IRQn     <----| interrupt control  +-> Goertzel harmonic engine   |
              +---------------------------------------------------+
```

Capture, raw moment accumulation, RMS, active power/energy, snapshot readout,
and interrupt handshake are implemented today. Calibration, phase/frequency
tracking, event detection, reactive/apparent measurements, and harmonics are
staged in the [architecture](docs/architecture.md), not claimed as complete.

## Why this architecture

The practical target is an open, single-phase **ADE9153A-like digital
companion**, while using the **ADE9430** as the power-quality feature ceiling.
The external ADS131M02 keeps the precision analog and delta-sigma conversion
off-chip. This leaves the tapeout focused on deterministic metrology, exposed
intermediate results, selectable harmonic bins, waveform streaming, and
calibration that users can inspect and reproduce.

For harmonics, the intended implementation is phase-locked resampling plus a
time-multiplexed **Goertzel/sliding-DFT engine**. It calculates selected DFT
bins without paying the RAM and butterfly cost of a general FFT.

## Measurement output

The current RTL exposes 64-bit raw moments over a second SPI port. For a
256-sample window:

```text
Vmean = sum(v) / 256
Imean = sum(i) / 256
Praw  = sum(v*i) / 256
Vrms  = sqrt(sum(v^2) / 256)
Irms  = sqrt(sum(i^2) / 256)
Sraw  = Vrms * Irms
PF    = Praw / Sraw
```

The ASIC now calculates raw-count `VOLTAGE_RMS`, `CURRENT_RMS`,
`ACTIVE_POWER`, and signed cumulative `ACTIVE_ENERGY`. Physical volts,
amperes, watts, and watt-hours are obtained by applying CT/VT calibration
coefficients and the sample period. Read `MEASUREMENT_SEQ` before and after a
multi-register transfer and retry if it changed. See the complete
[register map](docs/register-map.md).

## FPGA validation

- **FabricFox / iCE40UP5K:** preferred low-cost PMOD bench for the current
  SPI capture and serialized arithmetic core. The reproducible seed-10 build
  routes at 2,620 of 5,280 logic cells (49%) and reaches 25.33 MHz, leaving
  all block RAM and SPRAM available for event and waveform buffering.
- **OrangeCrab ECP5-25F:** recommended full-pipeline target with comfortable
  room for event buffering and a 15-bin Goertzel engine.
- **ECP5-85F board:** fallback for parallel comparison engines, long waveform
  buffers, or a full FFT reference implementation.

The ASIC build requests the maximum `8x2` SKY130 template allocation. Actual
area and timing reports will decide which Stage 1 features remain in the
tapeout; the FPGA reference can retain the complete architecture.

## Build and test

```sh
cd test
python3 -m pip install -r requirements.txt
make -B
```

The test requires Icarus Verilog. Tiny Tapeout GitHub Actions run simulation,
GDS hardening, documentation, and FPGA checks automatically. See the
[utilization review](docs/utilization-review.md) for the optimization rationale
and measured FabricFox results.

## References

- [TI ADS131M02](https://www.ti.com/product/ADS131M02)
- [TI MSPM0 energy metrology architecture](https://software-dl.ti.com/msp430/esd/MSPM0-SDK/latest/docs/english/middleware/energy_metrology/doc_guide/doc_guide-srcs/Energy_Metrology_SW_Overview.html)
- [Analog Devices ADE9430](https://www.analog.com/en/products/ade9430.html)
- [Analog Devices ADE9153A](https://www.analog.com/en/products/ade9153a.html)
- [Analog Devices ADE9000](https://www.analog.com/en/products/ade9000.html)
- [Tiny Tapeout HDL templates](https://tinytapeout.com/hdl/templates/)

Licensed under Apache-2.0.
