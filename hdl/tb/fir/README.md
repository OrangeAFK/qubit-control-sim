# FIR testbench (Phase 3)

Stimulus and expected vectors are **derived from checked-in Phase 2 fixtures**
(`python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz`), not invented in the TB.
Decimation **M = 4** is folded into this stage (emit every M-th filtered sample).

## Layout

| path | role |
|------|------|
| `tb_fir.sv` | Module testbench (reset, 100 MHz clk, stimulus, compare window) |
| `export_fixtures.py` | NPZ → Q1.14 `$readmemh` hex + `vectors/fir_params.svh` |
| `vectors/` | Generated mem files + params (regenerate via export script) |
| `../../rtl/fir/fir.v` | Empty shell for elaborate only — **not** the FIR DUT |

## Regenerate vectors

From repo root (with `cryocontrol` importable)::

```bash
python hdl/tb/fir/export_fixtures.py
```

| vector | derivation |
|--------|------------|
| `*_in_{i,q}.mem` | `quantize_Q1.14(dsp_ref.ddc(fixture_IF))` |
| `*_exp_{i,q}.mem` | `quantize_Q1.14(decimate(apply_fir(baseband, fir_coeffs), M))` |
| `fir_coeffs.mem` | `quantize_Q1.14(fixture fir_coeffs)` (63 taps, unity DC) |

Tolerance **8 LSB** (`docs/fixed_point_notes.md` § fir). Cases: `noiseless_s0`,
`noiseless_s1`, `noisy` (n_in=4096 → n_out=1024).

## Run simulation (xsim)

Source Vivado settings, then from repo root::

```bash
# Windows example:
#   call C:\Xilinx\2025.1\Vivado\settings64.bat
vivado -mode batch -source hdl/vivado/sim_fir.tcl
```

With the empty shell: expect TIMEOUT / FAIL (no `out_valid`) — that is the
correct pre-DUT outcome. With real FIR RTL: expect
`=== tb_fir: ALL CASES PASSED ===` within `FIR_TOL_LSB`.

Note: xsim 2025.1 corrupts `localparam string` arrays from `fir_params.svh`;
`tb_fir.sv` resolves case names via `case_name()` instead of `FIR_CASE_NAMES`.

## STOP — TB review before DUT

Do not replace `hdl/rtl/fir/fir.v` with real FIR logic until this testbench
(reset, clock, stimulus, compare window, fixture wiring) has been human-reviewed.
