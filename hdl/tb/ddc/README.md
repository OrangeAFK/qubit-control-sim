# DDC testbench (Phase 3)

Stimulus and expected vectors are **derived from checked-in Phase 2 fixtures**
(`python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz`), not invented in the TB.

## Layout

| path | role |
|------|------|
| `tb_ddc.sv` | Module testbench (reset, 100 MHz clk, stimulus, compare window) |
| `export_fixtures.py` | NPZ → Q1.14 `$readmemh` hex + `vectors/ddc_params.svh` |
| `vectors/` | Generated mem files + params (regenerate via export script) |
| `../rtl/ddc/ddc.v` | DUT (NCO mixer); see `hdl/rtl/ddc/README.md` |

## Regenerate vectors

From repo root (with `cryocontrol` importable)::

```bash
python hdl/tb/ddc/export_fixtures.py
```

Expected golden = `quantize_Q1.14(dsp_ref.ddc(fixture_IF))`. Tolerance **4 LSB**
(`docs/fixed_point_notes.md` § ddc).

## Run simulation (xsim)

Source Vivado settings, then from repo root::

```bash
vivado -mode batch -source hdl/vivado/sim_ddc.tcl
```

Expect `=== tb_ddc: ALL CASES PASSED ===` within `DDC_TOL_LSB`.

Note: xsim 2025.1 corrupts `localparam string` arrays from `ddc_params.svh`;
`tb_ddc.sv` resolves case names via `case_name()` instead of `DDC_CASE_NAMES`.
