# tb/axi_interface

## axis_if_ingress

`tb_axis_if_ingress.sv` — AXI-Stream IF ingress vs Phase 3 readout_chain input
vectors (`../readout_chain/vectors/`).

Run (repo root, Vivado `settings64` sourced):

```text
vivado -mode batch -source hdl/vivado/sim_axis_if_ingress.tcl
```

Expect: `tb_axis_if_ingress: ALL CASES PASSED`.
