"""PS↔PL hardware driver layer (Phase 4+).

Only this package may touch FPGA registers. See ``axi_lite_regs`` for the frozen
Phase 4 readout AXI-Lite map (ARCHITECTURE.md §3.3.1).
"""

from cryocontrol.hardware.axi_lite_regs import (
    BASE_ADDR_TENTATIVE,
    MAP_SIZE_BYTES,
    REGS,
    REG_BY_NAME,
    REG_BY_OFFSET,
    CtrlBits,
    StatusBits,
    ResultMetaBits,
)

__all__ = [
    "BASE_ADDR_TENTATIVE",
    "MAP_SIZE_BYTES",
    "REGS",
    "REG_BY_NAME",
    "REG_BY_OFFSET",
    "CtrlBits",
    "StatusBits",
    "ResultMetaBits",
]
