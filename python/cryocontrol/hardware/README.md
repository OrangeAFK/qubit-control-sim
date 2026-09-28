# hardware

PS↔PL driver: AXI-Lite config/status, AXI-Stream sample I/O. Phase 4/5. Only place
allowed to touch hardware registers.

**Frozen Phase 4 readout map:** `axi_lite_regs.py` (mirrors ARCHITECTURE.md §3.3.1).
Full driver (push samples / configure / read back) is a later Phase 4 task — do not
add register pokes outside this package.
