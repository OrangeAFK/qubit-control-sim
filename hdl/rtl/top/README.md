# cora_readout_pl

Synthesizable PL wrapper for Phase 4 readout on Digilent **Cora Z7-07S**
(`xc7z007sclg400-1`).

## Contents

| File | Role |
|------|------|
| `cora_readout_pl.v` | Top: `axi_lite_regs` + `axis_if_ingress` + `readout_chain` |

## Scope (first synth)

**In:** fabric DSP path, AXI-Lite stub (frozen map), AXI-Stream IF slave ports,
100 MHz `pl_clk` constraint. Built **out-of-context** (ports virtual) so
resource/timing of the DSP core can be measured without exceeding the
xc7z007s user-I/O pin budget.

**Out of scope (next / manual):** Zynq PS Block Design, AXI DMA MM2S, address
editor export, full-chip bitstream programming, on-hardware vector match.
Attach this module as RTL in a BD when ready; Lite base tentative `0x43C0_0000`
(ARCHITECTURE.md §3.3.1).

**Known gap:** Lite `INTEGRATE_START` / `INTEGRATE_LENGTH` are stored for
software visibility; the chain still uses compile-time parameters (defaults
8 / 1016). Runtime window ports are a later RTL change.

## Build

See `hdl/vivado/README.md` — `synth_cora_readout.tcl`.
