## ============================================================
## Cora Z7-07S (xc7z007sclg400-1) — Phase 4 readout PL wrapper (OOC)
## First synth is out-of-context: Lite/AXIS ports are virtual (not package
## pins). Full-chip pinout comes with Zynq PS Block Design + DMA later.
## 100 MHz pl_clk matches Phase 3 xsim.
## ============================================================

## Part is set in synth_cora_readout.tcl: xc7z007sclg400-1

create_clock -period 10.000 -name pl_clk [get_ports pl_clk]

## Async reset into fabric flops
set_false_path -from [get_ports rst_n]

## AXI / AXIS ports are unconstrained I/O delays for this first DSP-core
## build (PS/DMA timing comes with Block Design integration later).
