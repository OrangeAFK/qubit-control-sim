# vivado

Non-project-mode TCL build/synthesis/report-generation scripts.

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
