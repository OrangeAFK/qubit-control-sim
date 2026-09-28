# axi_interface / axis_if_ingress

AXI4-Stream IF sample ingress for Phase 4 readout on Cora Z7-07S.

## Modules

| File | Role |
|------|------|
| `axis_if_ingress.v` | AXI-Stream slave → `readout_chain`-style `m_valid`/`m_i`/`m_q` |
| `axi_lite_regs.v` | AXI4-Lite slave stub for the frozen map (ARCHITECTURE.md §3.3.1) |

Offsets also mirrored in `python/cryocontrol/hardware/axi_lite_regs.py`.
PL top that wires Lite + Stream + `readout_chain`: `hdl/rtl/top/cora_readout_pl.v`
(synth via `hdl/vivado/synth_cora_readout.tcl`).

## Stream packing and handshake

See ARCHITECTURE.md §3.3.1 **Stimulus path** and `docs/fixed_point_notes.md`
§ `axis_if_ingress`.

- **`TDATA`:** `{Q[15:0], I[15:0]}` — I in `[15:0]`, Q in `[31:16]`, signed Q1.14
- **`TVALID` / `TREADY`:** transfer when both 1; `TREADY = accept` (and not reset)
- **`TLAST`:** last beat of one acquisition buffer; native `m_last` pulses that beat
- **Latency:** one clock from AXIS accept → `m_valid`

## How the PS loads vectors

1. Quantize Phase 1/2 float IQ to int16 Q1.14 (same as Phase 3 fixtures).
2. Pack little-endian `uint32` words: `(Q_u16 << 16) | I_u16` into a contiguous
   DDR buffer of `N` words (`N * 4` bytes). Fixture length: 4096.
3. Cache-clean the buffer; program Lite config (`PHASE_*`, `THRESHOLD`, integrate
   window); pulse `CTRL.ARM`.
4. Start DMA MM2S with BTT = `N*4`, `TLAST` on the final beat into this slave.
5. Poll `STATUS.DONE`; read `RESULT_*`. `IF_SAMPLE_COUNT` should equal `N` once
   the Lite wrapper wires `sample_count`.

Bring-up without DMA: drive the same Stream ports from a PL harness or xsim TB.

## Testbench

`hdl/tb/axi_interface/tb_axis_if_ingress.sv` — streams Phase 3
`readout_chain/vectors/*_in_{i,q}.mem` into the slave, checks unpack / count /
`m_last`, with a TVALID gap and mid-stream backpressure.

```text
vivado -mode batch -source hdl/vivado/sim_axis_if_ingress.tcl
```
