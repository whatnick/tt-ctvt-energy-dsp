# Architecture and roadmap

## Benchmark

The design uses three Analog Devices families as reference points:

| Benchmark | Functions to learn from |
|---|---|
| [ADE9153A](https://www.analog.com/en/products/ade9153a.html) | Single-phase RMS, P/Q/S, energy, PF, period, zero crossing, dip/swell, overcurrent, and host-friendly registers |
| [ADE9000](https://www.analog.com/en/products/ade9000.html) | Waveform buffering, cycle-resampled data, total/fundamental measurements, and harmonic workflows |
| [ADE9430](https://www.analog.com/en/products/ade9430.html) | State-of-the-art power-quality vocabulary: harmonics/interharmonics, THD, events, and multi-cycle measurements |

ADE9430 is the functional ceiling, not a claim of equivalence. The achievable
Tiny Tapeout goal is one voltage/current pair with an ADE9153A-like measurement
interface. Unlike an integrated metering ASIC, the analog front end and ADC
remain external and independently replaceable.

## Processing pipeline

1. **Acquisition:** synchronize `DRDYn`, clock the ADS131M02 response frame,
   check status/CRC, count missed frames, and timestamp accepted samples.
2. **Calibration:** subtract signed offset, apply fixed-point gain, saturate,
   and phase-align current using integer delay plus a fractional-delay FIR.
3. **Moments:** time-share one multiplier across `v*i`, `v^2`, and `i^2`;
   accumulate sums, peaks, and minima/maxima.
4. **Fundamental metrology:** derive RMS, active power, energy, frequency,
   zero crossings, phase, reactive/apparent power, and power factor.
5. **Events:** fast peak and RMS overcurrent, sag, swell, frequency limits,
   missing samples, and ADC communication faults.
6. **Power quality:** resample to a fixed number of points per measured cycle
   and run selected Goertzel/sliding-DFT bins for harmonic magnitude and THD.
7. **Readout:** publish a coherent shadow bank, waveform/event FIFO, sequence
   number, and level-triggered interrupt.

The ADS131M02 already performs delta-sigma conversion and SINC3 decimation.
This core consumes signed PCM samples; it does not duplicate the ADC decimator.
An 8 kSPS operating point leaves more than 3000 cycles per sample at 25 MHz,
making a serialized multiplier practical.

## Staged implementation

| Stage | Deliverable | Status |
|---|---|---|
| 0 | 72-bit ADC SPI capture, raw moments, host SPI snapshots, IRQ handshake | Implemented |
| 1 | Integer RMS, active power and signed 64-bit energy | Implemented |
| 1b | ADC CRC/errors, offset/gain/phase correction and split import/export energy | Next |
| 2 | Q/S/PF, frequency, phase angle, zero crossing, peaks, sag/swell/overcurrent and event records | Planned |
| 3 | Cycle resampling, selected harmonics 2-15, THD, waveform FIFO | Planned |
| Host/FPGA | Full FFT, interharmonic grouping, long waveform capture and golden-reference comparison | Planned |

## Harmonic engine

A general FFT is inefficient in the tapeout area because it needs coefficient
storage, sample RAM, butterfly control, and multiple complex operations.
Goertzel computes an exact DFT bin:

```text
s[n] = x[n] + 2*cos(2*pi*k/N)*s[n-1] - s[n-2]
```

After `N` phase-locked samples, the bin energy is formed from the two state
values. One coefficient/state RAM and one shared MAC can scan selected voltage
and current harmonics. A sliding DFT is an alternative when continuous tracking
of only a few bins matters more than block results.

The initial target is the fundamental and harmonics 2-15. Full FFT and
IEC-style interharmonic grouping stay in host software unless synthesis proves
ample area.

## Output measurements

The final interface is intended to publish:

- calibrated instantaneous voltage/current and peaks;
- RMS voltage/current;
- total and fundamental P, Q, S, PF, phase angle, and line frequency;
- signed active/reactive energy plus separate import/export totals;
- harmonic magnitudes, fundamental magnitude, and THD;
- sag, swell, overcurrent, zero-crossing, ADC CRC, missed-frame, and overflow
  events;
- raw or cycle-resampled waveform windows.

Final fixed-point targets are signed Q1.23 samples, Q2.30 RMS, signed Q4.28
power, signed Q1.31 PF, Q16.16 frequency in hertz, and signed Q9.23 phase in
degrees. Energy uses at least 64-bit integer power-sample quanta with explicit
scale registers and sticky overflow.

## FPGA validation

The iCE40UP5K on an iCEBreaker or UPduino has about 5K LUTs and eight hardware
multipliers. The current core, including both SPI interfaces, one
time-multiplexed 24x24 MAC, serial integer square root, RMS, active power, and
energy, synthesizes with Yosys to 3,688 LUT4s and 1,525 flip-flops. It
therefore fits as the preferred low-cost capture/metrology bench, but a
substantial harmonic engine will require aggressive sharing.

An OrangeCrab ECP5-25F is the recommended full validation target: roughly 24K
LUTs, embedded RAM, and 28 18x18 multipliers provide room for waveform buffers
and 8-15 Goertzel bins. The current Stage 1 baseline synthesizes to 7,294 ECP5
LUT4s and 1,527 flip-flops before device-specific multiplier optimization.
Use an ECP5-85F board if validating parallel harmonic engines or a full FFT
reference.

Both iCE40 and ECP5 have mature open Yosys/nextpnr flows. Validation should
compare cycle-for-cycle RTL output against Python/NumPy vectors containing DC
offset, calibration errors, ±1 power factor, phase offsets, distorted loads,
frequency ramps, missing samples, CRC faults, energy rollover, sag/swell, and
impulsive overcurrent.
