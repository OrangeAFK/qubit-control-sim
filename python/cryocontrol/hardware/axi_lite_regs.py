"""Frozen Phase 4 readout AXI-Lite register map.

Source of truth for offsets/reset/access mirrors ARCHITECTURE.md §3.3.1.
HDL and the future PS driver must match this module; do not fork a second map.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntFlag
from typing import Final, Literal, Tuple

Access = Literal["rw", "ro"]

# Tentative PS view of the PL slave (Vivado Address Editor may reassign).
BASE_ADDR_TENTATIVE: Final[int] = 0x43C0_0000
MAP_SIZE_BYTES: Final[int] = 0x100  # primary aperture; 0x100+ reserved for FIR bank

# Fixture-aligned defaults (Phase 2/3 golden vectors) — software should program these
# explicitly; INTEGRATE_* reset values in HDL match these so a bare reset is usable.
FIXTURE_PHASE_INC: Final[int] = 0x1999_999A
FIXTURE_PHASE0: Final[int] = 0x0000_0000
FIXTURE_THRESHOLD_Q12_14: Final[int] = 9_962_831
FIXTURE_INTEGRATE_START: Final[int] = 8
FIXTURE_INTEGRATE_LENGTH: Final[int] = 1016

VERSION_RESET: Final[int] = 0x0004_0001  # major=4, minor=1
MAGIC_RESET: Final[int] = 0x4352_4F34  # "CRO4"


class CtrlBits(IntFlag):
    """CTRL (0x00) write-1-to-pulse fields; reads return 0 for these bits."""

    SOFT_RST = 1 << 0
    ARM = 1 << 1
    CLR_DONE = 1 << 2


class StatusBits(IntFlag):
    """STATUS (0x04) live / sticky bits."""

    BUSY = 1 << 0
    DONE = 1 << 1
    OVERRUN = 1 << 2
    ARMED = 1 << 3


class ResultMetaBits(IntFlag):
    """RESULT_META (0x24) latched fields."""

    DECISION = 1 << 0


@dataclass(frozen=True)
class Reg:
    """One 32-bit AXI-Lite register."""

    name: str
    offset: int
    access: Access
    reset: int
    description: str


REGS: Final[Tuple[Reg, ...]] = (
    Reg("CTRL", 0x00, "rw", 0x0, "Soft reset / arm / clear-done (W1P fields)"),
    Reg("STATUS", 0x04, "ro", 0x0, "Busy / done / overrun / armed"),
    Reg("PHASE_INC", 0x08, "rw", 0x0, "NCO phase_inc = round(f_lo/fs * 2^32)"),
    Reg("PHASE0", 0x0C, "rw", 0x0, "NCO phase0 = round(phase0_rad/(2π) * 2^32)"),
    Reg("THRESHOLD", 0x10, "rw", 0x0, "State threshold, signed Q12.14"),
    Reg(
        "INTEGRATE_START",
        0x14,
        "rw",
        FIXTURE_INTEGRATE_START,
        "First post-decim sample index in integrate window",
    ),
    Reg(
        "INTEGRATE_LENGTH",
        0x18,
        "rw",
        FIXTURE_INTEGRATE_LENGTH,
        "Integrate window length (post-decim samples)",
    ),
    Reg("RESULT_I", 0x1C, "ro", 0x0, "Latched integrated I, signed Q12.14"),
    Reg("RESULT_Q", 0x20, "ro", 0x0, "Latched integrated Q, signed Q12.14"),
    Reg("RESULT_META", 0x24, "ro", 0x0, "Latched decision (bit0) + reserved"),
    Reg("DECIM_M", 0x28, "ro", 4, "Build-time FIR decimation factor"),
    Reg("NUM_TAPS", 0x2C, "ro", 63, "Build-time FIR tap count"),
    Reg("VERSION", 0x30, "ro", VERSION_RESET, "Map version {major:16, minor:16}"),
    Reg("MAGIC", 0x34, "ro", MAGIC_RESET, "Identity word ASCII 'CRO4'"),
    Reg(
        "IF_SAMPLE_COUNT",
        0x38,
        "ro",
        0x0,
        "IF samples accepted in current/last acquisition",
    ),
)

REG_BY_NAME: Final[dict[str, Reg]] = {r.name: r for r in REGS}
REG_BY_OFFSET: Final[dict[int, Reg]] = {r.offset: r for r in REGS}

# Names the Phase 4 driver / HDL must expose (PLAN: config + results for Phase 3 chain).
REQUIRED_REG_NAMES: Final[Tuple[str, ...]] = (
    "CTRL",
    "STATUS",
    "PHASE_INC",
    "PHASE0",
    "THRESHOLD",
    "INTEGRATE_START",
    "INTEGRATE_LENGTH",
    "RESULT_I",
    "RESULT_Q",
    "RESULT_META",
    "DECIM_M",
    "NUM_TAPS",
    "VERSION",
    "MAGIC",
    "IF_SAMPLE_COUNT",
)
