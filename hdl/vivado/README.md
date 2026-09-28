# vivado

Non-project-mode TCL: simulation, synthesis, and report generation.

## Simulation

| script | purpose |
|--------|---------|
| `sim_ddc.tcl` | xsim compile/elaborate/run for `hdl/tb/ddc/tb_ddc.sv` |
| `sim_fir.tcl` | xsim compile/elaborate/run for `hdl/tb/fir/tb_fir.sv` |
| `sim_integration.tcl` | xsim for `hdl/tb/integration/tb_integration.sv` |
| `sim_state_discrim.tcl` | xsim for `hdl/tb/state_discrim/tb_state_discrim.sv` |
| `sim_readout_chain.tcl` | xsim for `hdl/tb/readout_chain/tb_readout_chain.sv` |
| `sim_axis_if_ingress.tcl` | xsim for `hdl/tb/axi_interface/tb_axis_if_ingress.sv` |

```bash
vivado -mode batch -source hdl/vivado/sim_ddc.tcl
vivado -mode batch -source hdl/vivado/sim_fir.tcl
vivado -mode batch -source hdl/vivado/sim_integration.tcl
vivado -mode batch -source hdl/vivado/sim_state_discrim.tcl
vivado -mode batch -source hdl/vivado/sim_readout_chain.tcl
vivado -mode batch -source hdl/vivado/sim_axis_if_ingress.tcl
```

Requires Vivado `xvlog`/`xelab`/`xsim` on `PATH` (source Vivado `settings64`).
Vectors: run the matching `python hdl/tb/<module>/export_fixtures.py` first if
the `vectors/` dir is missing.

## Synthesis + implementation (Phase 4 Cora readout)

| item | value |
|------|--------|
| Script | `hdl/vivado/synth_cora_readout.tcl` |
| Top | `cora_readout_pl` (`hdl/rtl/top/cora_readout_pl.v`) |
| Part | `xc7z007sclg400-1` (Cora Z7-07S) |
| Constraints | `hdl/vivado/constraints/cora_z7_07s_readout.xdc` (100 MHz `pl_clk`) |
| Work / DCP | `hdl/vivado/out_cora_readout/` |
| Checked-in reports | `docs/reports/phase4_readout_<YYYY-MM-DD>.txt` (+ `_utilization.rpt`, `_timing.rpt`) |

### Exact commands (Windows)

From the **repo root**:

```bat
call C:\Xilinx\2025.1\Vivado\settings64.bat
vivado -mode batch -source hdl/vivado/synth_cora_readout.tcl
```

Linux / Git Bash equivalent: `source <Vivado>/settings64.sh` then the same
`vivado -mode batch ...` line.

### What the TCL does

1. Reads Phase 3 RTL (`ddc`, `fir`, `integration`, `state_discrim`,
   `readout_chain`) plus Phase 4 `axis_if_ingress`, `axi_lite_regs`, and top
   `cora_readout_pl`.
2. Stages `fir_coeffs.mem` into the run directory (FIR `$readmemh`).
3. `synth_design -mode out_of_context` → `opt` → `place` → `route` for
   `xc7z007sclg400-1`. OOC is required: the Lite+AXIS port count exceeds the
   part's user I/O budget if every bit is a package pin; PS/DMA attach later
   uses interconnect, not 125 PL IOBs.
4. Writes utilization + timing summary under `out_cora_readout/` and copies a
   combined report into `docs/reports/`.

### Latest checked-in run (2026-09-27 DDC pipe, Vivado 2025.1)

Real OOC synth+impl of `cora_readout_pl` on `xc7z007sclg400-1` after FIR
registered-product MAC + **6-stage DDC** (interp reg + quadrant + mix-product
reg):

| metric | value |
|--------|--------|
| Slice LUTs | 6915 / 14400 (48%) |
| Slice Registers | 3018 / 28800 (10%) |
| Block RAM (RAMB18) | 17 / 100 (17%) |
| DSP48E1 | 42 / 66 (64%) |
| Timing @ 100 MHz | **met** — WNS **+0.149 ns** (critical: FIR eng → DSP RSTP) |
| Preferred PL clock | **100 MHz** |

Prior same-day: DDC interp-only WNS −0.600 ns (`…_ddcpipe_interp*`); FIR
product-pipe −2.464 ns (`…_productpipe*`); BRAM FIR −4.524 ns (`…_bram*`);
pipelined snap-mux −5.597 ns (`…_pipelined*`); pre-pipeline −16.889 ns
(`…_pre_pipeline*`). Latest: `phase4_readout_2026-09-27_ddcpipe*`. This is
**not** a board bitstream and does **not** claim on-hardware match.

### Out of scope

- Zynq PS Block Design / AXI DMA / programming the Cora
- Claiming on-hardware I/Q match (next Phase 4 task, human + board)

If synth/impl fails (license, part, tool), keep this TCL + README; do **not**
invent a timing report. PLAN.md Vivado checkbox stays unchecked until a real
report exists under `docs/reports/`.
