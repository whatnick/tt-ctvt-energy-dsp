# Utilization review and optimization decisions

This document captures the 22 September 2026 design review by
[Joel Stanley (`@shenki`)](https://github.com/shenki), together with the
implementation decisions and measured outcome. The original review was
delivered by email and supplied as a PDF; this Markdown version is the
maintained project record.

The review identifies the combinational multiplier and host SPI register mux
as the dominant consumers in the iCE40UP5K build. It recommends serialization,
right-sized arithmetic, shared adders, FPGA DSP inference, and synchronous
reset.

## Reviewed baseline

Joel reported the following reproducible FabricFox build:

- Design: `tt_um_whatnick_ctvt_energy_dsp`
- Reported revision: `main @ d843875`
- Flow: Yosys 0.69 `synth_ice40 -DSYNTH`, nextpnr-ice40 with UP5K SG48,
  seed 10, 12 MHz, and the FabricFox v2 pin map

The reported revision was not present in the public repository when this
review was integrated. The measured baseline nevertheless agrees with public
`main` at `7c8eb36`.

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Logic cells | 4,479 | 5,280 | 84% |
| `SB_MAC16` DSPs | 0 | 8 | 0% |
| Block RAMs | 0 | 30 | 0% |
| I/O cells | 26 | 39 | 66% |

The flattened baseline contained 3,777 LUT4s, 1,590 flip-flops, and 623 carry
cells. Routed Fmax was 15.8 MHz: sufficient for the review's 12 MHz build but
below the 25 MHz clock declared in `info.yaml`.

### Baseline module distribution

| Module | LUT4 | Flip-flops | LUT share |
|---|---:|---:|---:|
| `energy_accumulator` | 2,511 | 828 | 61% |
| `host_spi_readout` | 889 | 157 | 22% |
| `integer_sqrt` | 267 | 168 | 6% |
| Top-level offset correction | 195 | 1 | 5% |
| `metering_postprocess` | 162 | 278 | 4% |
| `adc_spi_capture` | 98 | 158 | 2% |

Isolated synthesis attributed approximately 1,764 LUT4s to the combinational
signed 24x24 multiplier and 832 LUT4s to the 15-way 64-bit read mux.

## Review recommendations

### Serialize the multiplier

The accumulator uses one multiplier for `v*i`, `v^2`, and `i^2`. At the
ADS131M02 maximum 32 kSPS rate, a 25 MHz core has about 781 cycles per sample.
A 24-cycle shift-and-add operation uses 72 cycles for all three products,
leaving ample acquisition and accumulation margin.

This replaces the large combinational multiplier with one 48-bit adder and
shortens the critical path. It benefits both FPGA emulation and the SKY130
ASIC.

### Enable FPGA DSP inference

Adding `-dsp` to `synth_ice40` mapped the original 24x24 multiplier to four of
the UP5K's eight `SB_MAC16` blocks:

| Flow | Logic cells | Fmax |
|---|---:|---:|
| Baseline | 4,479 (84%) | 15.8 MHz |
| Baseline RTL with `-dsp` | 2,760 (52%) | 28.5 MHz |

This is an FPGA-only safeguard. The portable RTL must not instantiate
`SB_MAC16`, and the ASIC gains nothing from this flag.

### Reduce host SPI selection width

The review proposed constructing the 64-bit response over multiple core
cycles using a byte-wide register selector. The host interface is limited to
2 MHz against a 25 MHz core, allowing work between SPI edges without changing
the register map.

### Right-size finite-window arithmetic

For 256 signed 24-bit samples:

- product and square sums use 56 bits;
- signed linear sums use 32 bits;
- averaged square radicands use 48 bits;
- integer square-root results use 24 bits;
- window-average active power uses 56 bits.

The SPI interface continues returning 64-bit words by sign-extending or
zero-extending these internal values.

### Share accumulation hardware

The baseline performs five wide additions in parallel. Serial accumulation
states allow a single 56-bit adder to update active power, voltage, current,
voltage squared, and current squared. The extra cycles are insignificant
relative to the sample period.

### Remove redundant sample storage and fold calibration into the datapath

ADC output samples remain stable until the next completed frame, so the
accumulator does not need another 48-bit input latch. Offset subtraction and
saturation can also share one calibration subtractor over two states.

### Use synchronous reset

Tiny Tapeout supplies reset synchronously to the project clock. Using
synchronous reset allows the SKY130 flow to use smaller plain flip-flops
instead of async-reset variants. This optimization requires reset and
gate-level regression testing.

## Implementation decisions

The implementation follows the review with two deliberate refinements:

1. **Cumulative active energy remains signed 64-bit.** A finite-window result
   can safely use 56 bits, but cumulative energy cannot: a 56-bit accumulator
   can overflow after only two worst-case full-scale windows. The future
   calibrated interface should add explicit scaling and sticky overflow.
2. **SPI selects one byte at each transmitted byte boundary.** An attempted
   eight-cycle preload inferred more logic with the current register-bank
   shape. Boundary loading still reduces selection width, preserves the
   protocol, and does not depend on an undocumented turnaround interval.

The FPGA Makefile retains `synth_ice40 -dsp` as protection against future
FPGA-only arithmetic, although the serialized multiplier itself uses no hard
DSP blocks.

## Integrated result

The optimized design, including both SPI interfaces, calibration, raw
moments, RMS, active power, cumulative energy, snapshots, and IRQ, routes on
FabricFox at:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Logic cells | 2,620 | 5,280 | 49% |
| `SB_MAC16` DSPs | 0 | 8 | 0% |
| Block RAMs | 0 | 30 | 0% |
| SPRAM blocks | 0 | 4 | 0% |

With seed 10, routed Fmax is 25.33 MHz and passes the declared 25 MHz target.
The serial multiplier, shared accumulator adder, shared calibration
subtractor, right-sized datapaths, synchronous resets, and byte-oriented SPI
readout are all included in this result.

## Reproduction

```sh
cd fpga
make report
make bitstream
```

The generated bitstream is
`fpga/build/tt_um_whatnick_ctvt_energy_dsp.bin`.

Thanks to Joel Stanley (`@shenki`) for the detailed utilization analysis and
optimization recommendations.
