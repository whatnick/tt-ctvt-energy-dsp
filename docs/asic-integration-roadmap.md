# GF180 ASIC integration roadmap

## Target

- Service: Tiny Tapeout GF, manufactured through wafer.space
- PDK: `gf180mcuD`
- Standard cells: `gf180mcu_fd_sc_mcu7t5v0`
- Allocation: `4x4`
- Nominal project clock: 16.384 MHz
- ADC master clock: 4.096 MHz
- Flow: LibreLane/OpenROAD through the shuttle-pinned
  `TinyTapeout/tt-gds-action`

The project remains a Tiny Tapeout user macro. The standalone wafer.space
pad-ring template is a reference for GF180 practices but is not used to build
this macro.

## Integration boundaries

```text
uio PMOD
  -> ADS clock/reset/SPI
  -> validated sample stream
  -> calibration
  -> serialized MAC and moments
  -> RMS/power/energy
  -> optional harmonic engine
  -> snapshot/event/waveform bank
  -> selected host transport
  -> ui_in / uo_out
```

Each boundary uses a valid/ready or request/acknowledge contract. No module may
silently discard a sample, command, event or waveform byte.

## Milestones

### A0: GF180 infrastructure

- Keep devcontainer, PDK, gate models and GDS action on the same shuttle tag.
- Generate a legal `4x4` user configuration.
- Run lint, synthesis and early floorplanning on every architectural change.
- Archive synthesis, timing, congestion and cell-count reports as CI
  artifacts.

Exit: synthesis and placement complete with no inferred latches, combinational
loops or unconstrained clocks.

### A1: Direct PMOD acquisition

- Use the standard SPI ordering on `uio[0:3]`.
- Drive DRDY, RESETn and CLK_HOST on `uio[4:6]`.
- Add explicit ADS131M02 MODE, CLOCK, GAIN and channel configuration.
- Verify command responses and optional CRC.
- Count missed frames, invalid status, CRC errors and sample overruns.

Exit: repeated power/reset/configure/capture cycles pass on FPGA hardware and
in the ADS behavioral model.

### A2: Metrology baseline

- Retain one serialized signed multiplier and one shared adder.
- Freeze fixed-point widths from measured analog scaling.
- Add gain and phase calibration.
- Add separate import/export energy and sticky overflow.
- Preserve coherent snapshots and sequence numbers.

Exit: randomized 50/60 Hz vectors agree with the Python golden model within
the documented integer error bounds.

### A3: Host transport

Build and compare:

1. legacy SPI only;
2. UART only;
3. UART plus parallel waveform FIFO.

The UART build is preferred if it is smaller than SPI and passes the onboard
USB workflow. The parallel FIFO is retained only when waveform throughput is
required.

Exit: selected transport passes RTL, FPGA and GF gate-level tests and has a
working RP2040/RP2350 client.

### A4: Harmonic area matrix

Synthesize a parameter matrix:

| Build | Harmonic states |
|---|---:|
| Base | 0 |
| H1 | 1 programmable bin per channel |
| H2 | 2 programmable bins per channel |
| H4 | 4 programmable bins per channel |
| H8 | 8 programmable bins per channel |

The FPGA reference computes bins 1 through 15. ASIC coefficients are written
by the host, avoiding an on-chip cosine generator. State storage and the
serialized coefficient multiplication are shared.

Retain the largest build satisfying:

- placement density below 70%;
- no global-routing overflow;
- positive setup and hold slack at 16.384 MHz;
- at least 10% spare sequential and combinational area;
- clean DRC, LVS and Tiny Tapeout precheck; and
- complete gate-level regression.

If even H1 misses those margins, waveform or moment data is exported and the
host performs harmonic analysis.

### A5: Signoff

- Reset and clock-domain-crossing review.
- All asynchronous inputs pass through documented synchronizers.
- No result changes during an atomic host transfer.
- Long simulation covering sequence and energy counter rollover.
- Min/max signed arithmetic and saturation tests.
- Gate-level test at the GF slow and fast timing assumptions available to the
  flow.
- Final DRC, LVS, antenna, density and Tiny Tapeout precheck.
- Pin-level FPGA regression using the production protocol.

## Synthesis comparison table

Every architecture build records:

| Metric | Required record |
|---|---|
| Sequential cells | count and area |
| Combinational cells | count and area |
| Buffer/inverter share | count and area |
| Maximum placement density | percent |
| Worst setup/hold slack | nanoseconds |
| Global-routing overflow | count |
| Total wire length | micrometres |
| Clock-tree buffers | count |
| Power estimate | dynamic and leakage when available |
| DRC/LVS/precheck | pass/fail and violation count |

Comparisons use the same PDK revision, LibreLane version, floorplan, clock
constraint and random seeds.

## Measured GF180 baseline

The direct-Pmod SPI baseline completed LibreLane physical design using
LibreLane 2.4.2 and open_pdks GF180 revision
`0fe599b2afb6708d281543108caf8310912f54af`.

| Metric | Result |
|---|---:|
| Core area | 1,045,270 square micrometres |
| Standard-cell utilization | 27.241% |
| Standard-cell instances | 16,802 |
| Sequential cells | 1,437 |
| Clock buffers | 236 |
| Timing-repair buffers | 1,195 |
| Worst setup slack | 6.378 ns |
| Worst hold slack | 0.364 ns |
| Setup / hold violations | 0 / 0 |
| Detailed-routing DRC errors | 0 |
| Magic DRC errors | 0 |
| LVS errors | 0 |
| Functional GF gate-level regression | 1 passed, 0 failed |
| Estimated total power | 12.364 mW |

This establishes substantial area and timing headroom for transport changes
and a small harmonic engine. It is not yet a tapeout-clean signoff:

- three routed antenna violations remain;
- slow-corner maximum-slew checks report up to 481 violations;
- maximum-capacitance checks report up to 28 violations;
- maximum-fanout checks report up to 24 violations; and
- LibreLane 2.4.2 does not support KLayout DRC for `gf180mcuD`.

Routing-aware repair reduced maximum-capacitance violations from 42 to 28.
The remaining failures comprise both clock-tree branches and ordinary
high-fanout signals, so they require a custom flow/ECO repair after extracted
parasitics rather than progressively tighter global buffering. Binary FSM
encoding reduced sequential state storage and antenna repair reduced the
antenna result from six to three pins. The remaining pins are on calibration
offset nets.

The accepted configuration uses a 50% global-route antenna margin. An 80%
experiment reduced the final antenna result to one pin, but inserted 815
diodes and regressed the final checks to 38 capacitance, 850 slew and 150
fanout violations. Local calibration shadow registers also regressed setup
timing to three violations without improving capacitance. Both experiments
were rejected. LibreLane's targeted ECO-diode step was also rejected because
OpenROAD crashed while incrementally rerouting these nets.

The project now supplies explicit PnR and signoff SDC constraints. Remaining
electrical closure requires a selective post-extraction ECO flow or an updated
OpenROAD/LibreLane version with stable targeted diode and load-partitioning
support. Tiny Tapeout shuttle precheck must provide the additional DRC
coverage unavailable from KLayout in this tool version.

The extracted powered netlist passes the same cocotb metrology regression as
RTL. This is a functional gate-level result; annotated-delay/SDF testing and
the Tiny Tapeout precheck remain release requirements.

## Dockerized validation

The checked-in devcontainer pins the GF180 PDK selection, LibreLane version,
Tiny Tapeout support-tools revision and YoWASP FPGA tools.

Required validation sequence:

```sh
cd test
make -B

cd ../fpga
make clean
make report

cd ..
./tt/tt_tool.py --create-user-config --gf
# Run the hardening command defined by the selected GF shuttle.
./tt/tt_tool.py --print-warnings
```

The exact hardening command and tool versions follow the selected
`tt-gds-action` tag. Upgrading LibreLane or the PDK independently invalidates
area and timing comparisons.
