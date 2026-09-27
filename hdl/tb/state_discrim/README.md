# State-discrimination testbench (Phase 3)

Stimulus and expected vectors are **derived from checked-in Phase 2 fixtures**
(`python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz`) — not invented in
the TB.

## Layout

| path | role |
|------|------|
| `tb_state_discrim.sv` | Module testbench (reset, 100 MHz clk, stimulus, bit-exact compare) |
| `export_fixtures.py` | NPZ → Q12.14 in / 1-bit exp `$readmemh` + `vectors/state_discrim_params.svh` |
| `vectors/` | Generated mem files + params (regenerate via export script) |
| `../../rtl/state_discrim/state_discrim.v` | Empty shell for elaborate only — **not** the DUT |

## Regenerate vectors

From repo root (with `cryocontrol` importable)::

```bash
python hdl/tb/state_discrim/export_fixtures.py
```

| vector | derivation |
|--------|------------|
| `*_in_{i,q}.mem` | `quantize_Q12.14(fixture output_iq_*)` |
| `*_exp_decision.mem` | fixture `decision_*` / `decision` (0 or 1) |
| `SD_THRESHOLD_Q` | `quantize_Q12.14(fixture threshold)` (~608.083 → 9962831) |

Tolerance: **bit-exact** on the 1-bit decision (`docs/fixed_point_notes.md`
§ state_discrim). Cases: `noiseless_s0` (0), `noiseless_s1` (1), `noisy` (0).

## Run simulation (xsim)

Source Vivado settings, then from repo root::

```bash
# Windows example:
#   call C:\Xilinx\2025.1\Vivado\settings64.bat
vivado -mode batch -source hdl/vivado/sim_state_discrim.tcl
```

With the empty shell: expect TIMEOUT / FAIL (no `out_valid`) — that is the
correct pre-DUT outcome. With real state_discrim RTL: expect
`=== tb_state_discrim: ALL CASES PASSED ===` (bit-exact decisions).

Note: xsim 2025.1 corrupts `localparam string` arrays from
`state_discrim_params.svh`; `tb_state_discrim.sv` resolves case names via
`case_name()` instead of `SD_CASE_NAMES`.

## STOP — TB review before DUT

Do not replace `hdl/rtl/state_discrim/state_discrim.v` with real compare logic
until this testbench (reset, clock, stimulus, compare window, fixture wiring)
has been human-reviewed.
