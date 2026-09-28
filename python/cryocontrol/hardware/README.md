# hardware

PS↔PL driver: AXI-Lite config/status, AXI-Stream sample I/O. Phase 4/5. Only place
allowed to touch hardware registers.

**Frozen Phase 4 readout map:** `axi_lite_regs.py` (mirrors ARCHITECTURE.md §3.3.1).

**Driver:** `driver.ReadoutDriver` over a `HardwareBackend`:
- `MockBackend` — pytest / no board
- `MmioBackend` — Cora bring-up stub (requires a mapped view; DMA path not wired yet)

Packing (`packing.py`): `TDATA = {Q[15:0], I[15:0]}` signed Q1.14 per §3.3.1.

## On-hardware (blocked)

Full procedure, blockers (need PS+DMA bitstream; OOC design is not programmable;
timing fail at 100 MHz), and pass criteria: [`docs/phase4_on_hardware.md`](../../../docs/phase4_on_hardware.md).

Software-only dry-run (mock + fixtures, **not** Cora):

```text
python scripts/phase4_readout_dry_run.py
```
