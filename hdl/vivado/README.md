# vivado

Non-project-mode TCL build/synthesis/report-generation scripts.

## Simulation

| script | purpose |
|--------|---------|
| `sim_ddc.tcl` | xsim compile/elaborate/run for `hdl/tb/ddc/tb_ddc.sv` |
| `sim_fir.tcl` | xsim compile/elaborate/run for `hdl/tb/fir/tb_fir.sv` |

```bash
vivado -mode batch -source hdl/vivado/sim_ddc.tcl
vivado -mode batch -source hdl/vivado/sim_fir.tcl
```

Requires Vivado `xvlog`/`xelab`/`xsim` on `PATH` (source Vivado `settings64`).
Vectors: run `python hdl/tb/ddc/export_fixtures.py` or
`python hdl/tb/fir/export_fixtures.py` first if the matching `vectors/` dir
is missing.
