# GF180 silicon layout visuals

These images are rendered from the accepted LibreLane GF180 signoff GDS:

```text
runs/wokwi/final/gds/tt_um_whatnick_ctvt_energy_dsp.gds
```

| View | Inspection purpose |
|---|---|
| [Full composite](images/silicon-layout/01-full-composite.png) | Whole-macro outline, cell fabric, routing, and pad-access geometry |
| [Cell and FEOL](images/silicon-layout/02-cell-feol.png) | Standard-cell placement texture, active/poly/contact continuity, and whitespace |
| [Metal routing](images/silicon-layout/03-metal-routing.png) | Metal 1-4 routing distribution, congestion, and long interconnect |
| [Top-metal power](images/silicon-layout/04-top-metal-power.png) | Upper-metal power distribution and via transitions |
| [Center detail](images/silicon-layout/05-center-detail.png) | Enlarged central cell-and-routing detail for visual inspection |
| [Cell placement map](images/silicon-layout/06-cell-placement.png) | Functional logic (green), registers (blue), clock cells (yellow), buffers (purple), and antenna diodes (red), with filler cells suppressed |

These images are inspection aids, not signoff checks. The accepted build still
uses the machine-readable LibreLane/OpenROAD, Magic DRC, LVS, antenna, timing,
and extracted-parasitic reports as the signoff evidence.

Regenerate the images from the repository root using the pinned LibreLane
container:

```powershell
docker run --rm `
  -v "${PWD}:/work" `
  -w /work `
  ghcr.io/librelane/librelane:2.4.2 `
  python scripts/render_silicon_layout.py `
  runs/wokwi/final/gds/tt_um_whatnick_ctvt_energy_dsp.gds `
  docs/images/silicon-layout
```
