# Manufactured CTVT PMOD bring-up

This sequence commissions an assembled CTVT PMOD with the FPGA build before
using it to validate GF180 silicon. It does not authorize direct connection to
mains. Use only an isolated current transformer and a certified isolated
AC/AC transformer.

## 1. Incoming inspection

1. Compare the assembly with the KiCad renders and manufacturing BOM.
2. Confirm J1 and J4 orientation, U1 pin 1, and D1/D2 orientation.
3. Inspect the TSSOP pins, PMOD headers, jacks, precision resistors, and
   differential filter parts for bridges, tombstones, or substitutions.
4. Measure resistance between 3.3 V and GND before applying power. Investigate
   a near-short rather than relying on a current-limited supply to clear it.
5. Confirm continuity from the PMOD grounds and supply pins to TP7 and TP6.

Record the board serial number, PCB revision, assembly date, substitutions,
and photographs before rework.

## 2. Current-limited power-up

Power the board from a current-limited 3.3 V laboratory supply or a protected
FPGA PMOD port with no CT or transformer attached.

1. Confirm 3.3 V at TP6 and ground at TP7.
2. Check that U1 and the protection parts do not heat unexpectedly.
3. Verify the filtered analog supply at the ADC.
4. Remove power immediately if current is materially above the calculated
   idle expectation or the supply collapses.

## 3. FPGA digital bring-up

Use the FabricFox/iCE40 build first because it exercises the same PMOD mapping
as Tiny Tapeout:

```text
uio[0] CSn       uio[4] DRDYn
uio[1] DIN       uio[5] RESETn
uio[2] DOUT      uio[6] CLK_HOST
uio[3] SCLK      uio[7] reserved
```

With an oscilloscope or logic analyzer:

1. Confirm `RESETn` remains low for the programmed startup interval.
2. Confirm `CLK_HOST` is continuous and has the expected FPGA-derived rate.
3. Confirm `DRDYn` begins toggling after reset release.
4. Confirm each `DRDYn` event produces one 72-bit SPI transfer with clean
   `CSn`, `SCLK`, and `DOUT` levels.

Read the host registers:

| Register | Expected first result |
|---|---|
| `DEVICE_ID` (`0x00`) | `0x4354565444535031` |
| `ADC_STATUS` (`0x02`) | Stable ADS131M02 response/status word |
| `ADC_FRAME_COUNT` (`0x03`) | Increasing |
| `ADC_OVERRUN_COUNT` (`0x04`) | Zero |
| `ADC_DIAGNOSTICS` (`0x05`) | `0x9` while idle after at least one frame |

An increasing frame counter proves the entire clock/reset/DRDY/SPI path. A
nonzero overrun count means the configured output data rate and 72-bit SPI
transfer time are incompatible or the interface is being retriggered.

## 4. Analog zero-input checks

Leave both field inputs disconnected, then use the intended safe termination
for each test:

1. Capture raw voltage and current samples for several minutes.
2. Measure mean, RMS noise, peak-to-peak noise, drift, and outliers.
3. Confirm neither channel is railed or oscillating.
4. Program the measured offsets and confirm the corrected means approach zero.
5. Repeat after thermal stabilization and after power cycling.

Keep the raw captures. They establish the board-specific noise and offset
baseline needed to distinguish PCB, ADC, FPGA, and later ASIC behavior.

## 5. Isolated stimulus and calibration

Apply traceable, isolated low-voltage stimuli only.

1. Calibrate the voltage channel over several transformer-secondary levels.
2. Calibrate the current channel with a known CT secondary current or isolated
   current-injection fixture.
3. Sweep amplitude to check linearity and clipping margin.
4. Drive both channels from a common reference to measure relative phase.
5. Repeat at representative phase angles and 50/60 Hz.
6. Compare raw samples, RMS, active power, and accumulated energy with a
   software golden model and reference instrument.

Record ADC clock, output data rate, gain, filter mode, transformer, CT, burden,
temperature, and calibration coefficients with every dataset.

## 6. Gateware completion gates

Before using the PMOD as a silicon reference platform:

- implement and verify ADS131M02 register writes and readback after reset;
- lock the ADC clock, gain, output data rate, channel-enable, and filter
  configuration;
- validate response words and add optional frame CRC;
- expose sticky fault bits and host-controlled counter clearing;
- add waveform capture on the FPGA for sample-by-sample comparison;
- validate offset, gain, and fractional phase calibration; and
- publish measured accuracy and noise results.

## 7. FPGA-to-silicon comparison

Use the same PMOD, sensor fixture, stimulus, ADC configuration, host protocol,
and golden datasets for FPGA and ASIC tests.

1. Capture FPGA raw frames and processed results.
2. Replace only the digital processing target with the Tiny Tapeout ASIC.
3. Verify pin timing, register identity, frame count, and fault counters.
4. Replay identical stimuli and compare every 256-sample window.
5. Attribute differences first to clock/sample-rate configuration and fixed
   point behavior before investigating silicon defects.
6. Run voltage, temperature, reset, interrupted-frame, and long-duration
   energy-accumulation tests.

The FPGA implementation is the known-good behavioral reference. The PMOD is
the common analog stimulus path, so retaining its configuration and datasets
is essential for meaningful silicon comparison.
