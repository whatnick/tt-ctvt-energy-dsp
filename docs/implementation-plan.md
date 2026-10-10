# FPGA and Tiny Tapeout implementation plan

## Implemented baseline

The first hardware-facing milestone consists of:

- ADS131M02 frame capture over SPI;
- generated `CLK_HOST` and `RESETn` signals for the CTVT PMOD;
- one serialized signed 24x24 multiplier shared by active power and both
  square accumulations;
- one shared accumulation adder;
- 256-sample coherent result snapshots;
- integer RMS, active power and cumulative active energy;
- an SPI mode-0 host interface with transaction-latched 64-bit reads;
- a level interrupt with explicit acknowledgement.

The direct-Pmod FabricFox implementation uses 2,682 of 5,280 logic cells and
routes at 25.39 MHz against the 25 MHz FPGA target. No DSP, block RAM or SPRAM
resources are used.

The ADC currently uses its reset defaults and sends NULL command words while
reading each 72-bit status/voltage/current frame. Explicit ADS131M02 register
configuration, response validation and optional CRC are the next acquisition
features.

## Clocking

The Tiny Tapeout design declares a nominal 16.384 MHz core clock. With
`ADC_MCLK_DIV=2`, `adc_spi_capture` toggles `CLK_HOST` every two core clocks,
producing a 4.096 MHz ADC master clock. The SPI clock divider produces a
2.048 MHz ADC serial clock.

The FPGA wrapper can continue operating at 25 MHz for timing validation. Its
generated ADC clock is then 6.25 MHz, which is useful for functional bring-up;
metrology calculations must use the measured FPGA sample rate rather than the
ASIC nominal value.

## CTVT PMOD bring-up

1. Verify 3.3 V, analog supply filtering and ground continuity without the
   ADC connected to a signal source.
2. Verify `CLK_HOST`, `RESETn`, `CSn` and `SCLK` at the PMOD header.
3. Confirm the ADS131M02 status word and default frame length.
4. Add and verify register writes for MODE, CLOCK, GAIN and channel enable.
5. Enable response checks, missed-frame counting and optional CRC.
6. Measure shorted-input noise and DC offset.
7. Apply isolated low-voltage sine waves to each channel and calibrate gain.
8. Apply phase-shifted voltage/current vectors and calibrate channel phase.
9. Compare RMS, active power and accumulated energy against a software golden
   model and a reference instrument.

Never connect mains directly to the PMOD. Use an isolated CT and certified
isolated AC/AC transformer.

## FPGA targets

### FabricFox / iCE40UP5K

FabricFox is the mandatory first target because it exercises the Tiny Tapeout
pin contract directly and has enough remaining logic and all RAM resources
available. It validates:

- PMOD electrical connectivity;
- ADC startup and frame capture;
- host SPI read/write behavior;
- interrupt handling;
- serialized arithmetic; and
- live calibration.

### ECP5 reference

An ECP5-25F or larger target is the reference platform for long waveform
buffers and a full harmonic comparison engine. The ECP5 design should use the
same acquisition and register modules but may instantiate more parallel
multipliers and RAM-backed sample storage.

## Harmonic analysis

Harmonics remain an area-gated feature for the ASIC. The FPGA reference should
first implement voltage and current bins 1 through 15 and compare them against
NumPy.

The ASIC candidate uses host-programmable Goertzel coefficients. One engine is
time-multiplexed across a configurable number of channel/bin states:

```text
s[n] = x[n] + coefficient * s[n-1] - s[n-2]
```

Candidate builds should set `NUM_HARMONIC_BINS` to 1, 2, 4 and 8. The largest
configuration is retained only if the GF180 4x4 build meets all of these:

- placement density below 70%;
- no global-routing overflow;
- positive setup and hold slack at 16.384 MHz;
- clean Tiny Tapeout precheck, DRC and LVS;
- at least 10% spare sequential and combinational cell area; and
- complete gate-level regression.

If no candidate meets those margins, the ASIC exports calibrated waveform
samples or moments and the host performs harmonic analysis.

## Tiny Tapeout GF180 flow

This repository is a Tiny Tapeout user macro and therefore uses the
TinyTapeout GF template rather than the standalone wafer.space pad-ring
template.

- PDK: `gf180mcuD`
- Standard-cell library:
  `gf180mcu_fd_sc_mcu7t5v0`
- Allocation: `4x4`
- Nominal clock: 16.384 MHz
- Flow: LibreLane and OpenROAD through `tt-support-tools`
- CI action: the target GF shuttle version of `TinyTapeout/tt-gds-action`

The checked-in devcontainer provides Icarus, cocotb, Verilator, Verible,
LibreLane and the YoWASP iCE40 tools. Build it with VS Code Dev Containers or:

```sh
docker build -f .devcontainer/Dockerfile -t ctvt-energy-dsp .
```

Inside the container:

```sh
cd test
make -B

cd ../fpga
make clean
make report
```

For local ASIC hardening, clone `tt-support-tools` as `tt/`, create the user
configuration with the GF option, and run the same GF hardening command used
by the selected shuttle action. Tool and PDK revisions must remain aligned
with that action rather than being upgraded independently.

## Release gates

1. RTL regression, lint and FPGA timing pass.
2. FabricFox reads real ADS131M02 frames from an assembled CTVT PMOD.
3. Register configuration and readback pass after repeated resets.
4. Calibration and metrology agree with the golden model.
5. GF180 synthesis, placement and routing meet the margin requirements.
6. GF gate-level tests pass with SDF-equivalent timing assumptions.
7. Tiny Tapeout precheck, DRC and LVS pass.
8. Documentation records the final clock, sample rate, ADC configuration,
   fixed-point formats and host register protocol.

## Current validation status

| Check | Status |
|---|---|
| RTL cocotb metrology regression | Pass: 1 test, 0 failures |
| FabricFox FPGA synthesis and place-and-route | Pass: 2,682 / 5,280 logic cells; 25.39 MHz |
| Generic Yosys synthesis and structural check | Pass: no structural problems |
| GF180 LibreLane physical design | Completed through GDS and extracted views |
| GF180 setup and hold timing | Pass: 6.378 ns setup and 0.364 ns hold worst slack |
| Detailed-route DRC / Magic DRC / LVS | Pass: 0 / 0 / 0 errors |
| Functional GF180 gate-level regression | Pass: 1 test, 0 failures |
| Antenna / maximum slew / maximum capacitance | Blocked: 3 / 481 / 28 violations |
| Maximum fanout | Blocked: 24 violations |
| KLayout DRC | Unsupported for GF180 by LibreLane 2.4.2 |
| Tiny Tapeout precheck | Pending |
| Annotated-delay GF gate-level regression | Pending |

The current build proves the architecture synthesizes, routes, extracts and
preserves functional behavior in GF180. It is an engineering baseline rather
than a tapeout release until the blocked and pending checks are closed.
