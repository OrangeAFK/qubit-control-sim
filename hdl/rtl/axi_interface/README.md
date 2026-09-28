# axi_interface

AXI-Lite config/status + AXI-Stream IF sample path for Phase 4 readout on Cora Z7-07S.

**Register map (frozen):** ARCHITECTURE.md §3.3.1 and
`python/cryocontrol/hardware/axi_lite_regs.py`. Implement the Lite slave and Stream
wrapper against that map — do not invent offsets here.

RTL for this directory is a later Phase 4 task (after Stream ingestion / driver work
per PLAN.md). This README only anchors the interface ownership.
