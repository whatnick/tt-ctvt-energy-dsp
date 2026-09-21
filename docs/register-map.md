# Bootstrap SPI register map

This is the implemented Stage 0 read-only interface. It intentionally exposes
raw moments before the calibrated measurement register map is frozen.

## Transaction

The host uses SPI mode 0:

1. Assert `Host CSn`.
2. Send an 8-bit address, most-significant bit first.
3. Clock 64 additional bits; `Host MISO` returns the register value
   most-significant bit first.
4. Deassert `Host CSn`.

For a write, set address bit 7, send the remaining 7-bit register address,
then send one 32-bit data word most-significant bit first. Host SPI inputs pass
through two-stage synchronizers into the 25 MHz core-clock domain; keep host
SCLK at or below 2 MHz.

All measurement registers belong to the last completed 256-sample window.
Read `SNAPSHOT_SEQ`, read the required values, and read `SNAPSHOT_SEQ` again.
Retry if the sequence changed. `IRQn` stays low after a new snapshot until
`IRQ acknowledge` is high for one core clock.

## Registers

| Address | Name | Signed | Description |
|---:|---|:---:|---|
| `0x00` | `DEVICE_ID` | No | ASCII-like constant `0x4354565444535031` (`CTVTDSP1`) |
| `0x01` | `SNAPSHOT_SEQ` | No | Completed-window counter in bits 31:0 |
| `0x02` | `ADC_STATUS` | No | Last ADS response/status word in bits 23:0 |
| `0x10` | `SUM_ACTIVE_POWER` | Yes | Sum of signed `voltage * current` products |
| `0x11` | `SUM_VOLTAGE_SQ` | No | Sum of squared signed voltage samples |
| `0x12` | `SUM_CURRENT_SQ` | No | Sum of squared signed current samples |
| `0x13` | `SUM_VOLTAGE` | Yes | Sum of signed voltage samples |
| `0x14` | `SUM_CURRENT` | Yes | Sum of signed current samples |
| `0x20` | `MEASUREMENT_SEQ` | No | Completed post-processing counter in bits 31:0 |
| `0x21` | `VOLTAGE_RMS` | No | Integer RMS in raw ADC counts |
| `0x22` | `CURRENT_RMS` | No | Integer RMS in raw ADC counts |
| `0x23` | `ACTIVE_POWER` | Yes | Window-average `voltage * current` in raw count-squared units |
| `0x24` | `ACTIVE_ENERGY` | Yes | Cumulative signed sum of accepted `voltage * current` products |
| `0x40` | `VOLTAGE_OFFSET` | Yes | Signed 24-bit ADC-count offset subtracted before accumulation |
| `0x41` | `CURRENT_OFFSET` | Yes | Signed 24-bit ADC-count offset subtracted before accumulation |

Offset subtraction saturates at the signed 24-bit ADC limits rather than
wrapping. Program offsets before acquisition or while ADC frame delivery is
paused so one 256-sample window never contains two calibration configurations.

Unknown addresses return zero and unknown writes are ignored. The planned
interface expands to 16-bit addresses, burst auto-increment, gain/phase
calibration, latched multiword reads, interrupt status/mask registers, and an
optional host CRC.
