## How it works

CTVT Energy DSP controls an ADS131M02 on the Whatnick CTVT PMOD. When `DRDYn`
falls, the SPI master clocks a 72-bit response frame into the ASIC: one 24-bit
status word followed by signed 24-bit voltage and current samples.

The current implementation accumulates five raw moments over 256 simultaneous
samples:

- voltage and current sums for DC-offset estimation;
- voltage squared and current squared for RMS;
- voltage multiplied by current for active power.

At the end of each window, all accumulators are copied to a stable snapshot,
`SNAPSHOT_SEQ` increments, and `IRQn` remains low until `IRQ_ACK` is asserted.
A second SPI interface lets a host read each 64-bit result.

The planned processing stages add offset/gain correction, fractional phase
compensation, RMS, active/reactive/apparent energy, power factor, frequency,
phase angle, sag/swell/overcurrent events, and selected harmonics using a
serialized Goertzel engine.

## How to test

Connect the CTVT PMOD ADC signals to `ADC DOUT`, `ADC DRDYn`, `ADC CSn`,
`ADC SCLK`, and `ADC DIN`. Configure the ADS131M02 for a 72-bit frame containing
status, channel 0 voltage, and channel 1 current.

Use host SPI mode 0. Send an 8-bit register address MSB-first, then clock 64
additional bits to receive the selected value. Read `SNAPSHOT_SEQ` before and
after a group of result registers to confirm a coherent window. Assert
`IRQ_ACK` for at least one ASIC clock to release `IRQn`.

For simulation:

```sh
cd test
python3 -m pip install -r requirements.txt
make -B
```

## External hardware

- [Whatnick CTVT PMOD](https://github.com/whatnick/ctvt-pmod)
- TI ADS131M02 dual simultaneous-sampling 24-bit ADC
- SPI host controller
