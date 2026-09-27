# Integration testbench (Phase 3)

Stimulus and expected vectors are **derived from checked-in Phase 2 fixtures**
(`python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz`) via the dsp_ref
chain through integrate — not invented in the TB.

## Layout

| path | role |
|------|------|
| `tb_integration.sv` | Module testbench (reset, 100 MHz clk, stimulus, compare) |
| `export_fixtures.py` | NPZ → Q1.14 in / Q12.14 exp `$readmemh` + `vectors/integration_params.svh` |
| `vectors/` | Generated mem files + params (regenerate via export script) |
| `../../rtl/integration/integration.v` | Empty shell for elaborate only — **not** the DUT |

## Regenerate vectors

From repo root (with `cryocontrol` importable)::

```bash
python hdl/tb/integration/export_fixtures.py
```

| vector | derivation |
|--------|------------|
| `*_in_{i,q}.mem` | `quantize_Q1.14(decimate(apply_fir(ddc(fixture_IF), fir_coeffs), M))` |
| `*_exp_{i,q}.mem` | `quantize_Q12.14(integrate(decimated, start=8, length=1016))` (matches fixture `output_iq_*`) |

Tolerance **16384 LSB** (= abs error ≤ 1.0 in Q12.14; `docs/fixed_point_notes.md`
§ integration). Cases: `noiseless_s0`, `noiseless_s1`, `noisy` (n_in=1024 → one
integrated IQ each).

## Run simulation (xsim)

Source Vivado settings, then from repo root::

```bash
# Windows example:
#   call C:\Xilinx\2025.1\Vivado\settings64.bat
vivado -mode batch -source hdl/vivado/sim_integration.tcl
```

With the empty shell: expect TIMEOUT / FAIL (no `out_valid`) — that is the
correct pre-DUT outcome. With real integration RTL: expect
`=== tb_integration: ALL CASES PASSED ===` within `INT_TOL_LSB`.

Note: xsim 2025.1 corrupts `localparam string` arrays from
`integration_params.svh`; `tb_integration.sv` resolves case names via
`case_name()` instead of `INT_CASE_NAMES`.

## STOP — TB review before DUT

Do not replace `hdl/rtl/integration/integration.v` with real accumulation logic
until this testbench (reset, clock, stimulus, compare window, fixture wiring)
has been human-reviewed.
