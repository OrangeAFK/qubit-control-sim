# vivado

Non-project-mode TCL build/synthesis/report-generation scripts.

## Simulation

| script | purpose |
|--------|---------|
| `sim_ddc.tcl` | xsim compile/elaborate/run for `hdl/tb/ddc/tb_ddc.sv` |

```bash
vivado -mode batch -source hdl/vivado/sim_ddc.tcl
```

Requires Vivado `xvlog`/`xelab`/`xsim` on `PATH` (source Vivado `settings64`).
Vectors: run `python hdl/tb/ddc/export_fixtures.py` first if `hdl/tb/ddc/vectors/`
is missing.
