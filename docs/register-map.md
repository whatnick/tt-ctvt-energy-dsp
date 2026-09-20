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

Unknown addresses return zero. The bootstrap interface has no write
transactions or transaction CRC. The planned interface expands to 16-bit
addresses, 32-bit data, burst auto-increment, configuration/calibration
registers, latched multiword reads, interrupt status/mask registers, and an
optional host CRC.
