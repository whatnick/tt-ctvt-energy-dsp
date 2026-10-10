# Host interface and metrology output roadmap

## Host placement

During FPGA and Tiny Tapeout evaluation, the default host is the RP2040 or
RP2350 controller on the development board. It provides the project clock and
reset, communicates with the metrology core, and bridges data to a PC over
USB.

For a standalone instrument, the same protocol is implemented by a controller
on the carrier board, such as an RP2040, STM32, ESP32 or Linux SBC. The host is
not placed on the analog CTVT PMOD; keeping the PMOD limited to the isolated
analog front end and ADC reduces digital noise and preserves reuse.

The CTVT PMOD occupies the bidirectional connector:

| `uio` | CTVT signal | Direction at ASIC |
|---:|---|---|
| 0 | ADC CSn | Output |
| 1 | ADC DIN | Output |
| 2 | ADC DOUT | Input |
| 3 | ADC SCLK | Output |
| 4 | ADC DRDYn | Input |
| 5 | ADC RESETn | Output |
| 6 | ADC CLK_HOST | Output |
| 7 | Reserved | Input |

This leaves the dedicated input and output ports available to the host.

## Transport modes

The transport is separated from the measurement register bank. Acquisition,
calibration and DSP modules publish results to an internal register/FIFO
interface; SPI, UART and parallel transports consume the same interface.

Two mode bits are sampled from `ui_in[7:6]` during reset:

| Mode | Transport | Purpose |
|---:|---|---|
| `00` | Legacy SPI | Bring-up compatibility and deterministic register access |
| `01` | UART | Default USB control and telemetry path |
| `10` | Parallel FIFO | High-rate waveform extraction |
| `11` | Self-test | Pattern generator and transport diagnostics |

### Legacy SPI

The implemented bootstrap interface uses:

- `ui_in[2]`: CSn
- `ui_in[3]`: SCLK
- `ui_in[4]`: MOSI
- `ui_in[5]`: IRQ acknowledge
- `uo_out[5]`: MISO
- `uo_out[6]`: IRQn
- `uo_out[7]`: sample strobe

It remains available until UART and host firmware pass hardware validation.
SPI mode 0 is limited to 1 MHz because inputs are oversampled by the core
clock.

### UART control and telemetry

UART uses the Tiny Tapeout standard USB-serial mapping:

- `ui_in[3]`: RX
- `uo_out[4]`: TX
- `uo_out[6]`: optional IRQn
- `uo_out[7]`: overflow/activity indicator

The initial baud rate is 1 Mbaud. A framed binary protocol uses:

```text
COBS(
  version,
  message_type,
  flags,
  sequence[31:0],
  payload_length[15:0],
  payload[],
  crc16
) + 0x00 delimiter
```

Required commands:

- identify device and protocol version;
- read/write one or more registers;
- read a coherent measurement snapshot;
- configure ADC, calibration and event limits;
- acknowledge/clear events;
- start/stop waveform streaming;
- request transport and DSP self-tests.

Required asynchronous messages:

- measurement snapshot;
- event record;
- waveform block;
- ADC/CRC/overrun fault; and
- transport overflow.

At 1 Mbaud, approximately 100 kB/s of encoded data is available. Two 24-bit
channels at 8 kSPS require 48 kB/s before framing, so continuous raw streaming
is feasible if the host services the port continuously.

### Output-only parallel FIFO

Parallel mode uses the complete output-only port as a byte bus:

- `uo_out[7:0]`: data;
- `ui_in[0]`: read clock/strobe;
- `ui_in[1]`: chip select/stream enable;
- `ui_in[2]`: abort or FIFO reset;
- `ui_in[3]`: optional status request.

The host clocks one byte from the FIFO per read cycle. Packets use the same
header, sequence and CRC fields as UART, without COBS encoding. The RP2040 or
RP2350 captures the bus using PIO.

Parallel mode is optional. It is included only if long waveform capture is a
required use case and its output mux, FIFO and verification cost do not reduce
the harmonic configuration that fits the ASIC.

## Implementation phases

| Phase | Deliverable | Exit criterion |
|---|---|---|
| H0 | Direct `uio` CTVT mapping and legacy SPI | RTL and FPGA builds pass; Pmod plugs in directly |
| H1 | Internal transport-independent register/FIFO bus | Existing SPI regression passes without DSP changes |
| H2 | UART TX/RX and packet codec | Randomized commands, CRC faults and back-to-back packets pass |
| H3 | RP2040/RP2350 USB bridge firmware and Python client | Live measurements and calibration work over USB |
| H4 | Optional parallel FIFO mode | Sustained waveform capture has no loss at the target sample rate |
| H5 | Remove or retain legacy SPI based on area | GF180 comparison selects the smallest complete transport set |

## Validation

- Cocotb packet encode/decode and malformed-frame tests.
- Random command timing and reset during transactions.
- Snapshot atomicity while measurements update.
- UART clock-error testing at both FPGA and ASIC clock rates.
- FIFO overflow, underflow and host-stall testing.
- RP2040/RP2350 loopback and sustained USB transfer testing.
- Gate-level transport regression using the GF180 netlist.

Current status:

- H0 direct-Pmod mapping passes RTL simulation and the 25 MHz FPGA
  synthesis/place-and-route flow.
- The legacy SPI register transport passes both RTL and functional GF180
  gate-level regression.
- H1 through H5 remain planned; UART, packet framing, host firmware and the
  optional parallel FIFO are not yet implemented.
