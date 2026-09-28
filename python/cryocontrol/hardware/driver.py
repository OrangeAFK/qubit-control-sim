"""Phase 4 readout hardware driver: configure, push IF samples, read results.

Talks to a ``HardwareBackend`` (``MockBackend`` in pytest; ``MmioBackend`` stub
for later Cora bring-up). Register offsets come only from ``axi_lite_regs``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from cryocontrol.hardware.axi_lite_regs import (
    FIXTURE_INTEGRATE_LENGTH,
    FIXTURE_INTEGRATE_START,
    FIXTURE_PHASE0,
    FIXTURE_PHASE_INC,
    FIXTURE_THRESHOLD_Q12_14,
    MAGIC_RESET,
    REG_BY_NAME,
    VERSION_RESET,
    CtrlBits,
    ResultMetaBits,
    StatusBits,
)
from cryocontrol.hardware.backend import HardwareBackend
from cryocontrol.hardware.packing import pack_iq_words


@dataclass(frozen=True)
class ReadoutConfig:
    """Writable acquisition parameters (ARCHITECTURE.md §3.3.1 sequence step 1)."""

    phase_inc: int = FIXTURE_PHASE_INC
    phase0: int = FIXTURE_PHASE0
    threshold: int = FIXTURE_THRESHOLD_Q12_14  # signed Q12.14
    integrate_start: int = FIXTURE_INTEGRATE_START
    integrate_length: int = FIXTURE_INTEGRATE_LENGTH


@dataclass(frozen=True)
class ReadoutResult:
    """Latched results + status snapshot after an acquisition."""

    result_i: int  # signed Q12.14 bit pattern in low 26 bits (stored as u32)
    result_q: int
    result_meta: int
    status: int
    if_sample_count: int

    @property
    def decision(self) -> bool:
        return bool(self.result_meta & ResultMetaBits.DECISION)

    @property
    def done(self) -> bool:
        return bool(self.status & StatusBits.DONE)


class ReadoutDriver:
    """PS-side driver for the Phase 4 readout Lite + Stream stimulus path."""

    def __init__(self, backend: HardwareBackend) -> None:
        self._be = backend

    # --- low-level register helpers (offsets from axi_lite_regs only) ---

    def write_reg(self, name: str, value: int) -> None:
        reg = REG_BY_NAME[name]
        if reg.access != "rw":
            raise PermissionError(f"{name} is read-only")
        self._be.write_u32(reg.offset, value & 0xFFFF_FFFF)

    def read_reg(self, name: str) -> int:
        reg = REG_BY_NAME[name]
        return self._be.read_u32(reg.offset) & 0xFFFF_FFFF

    def pulse_ctrl(self, *bits: CtrlBits) -> None:
        mask = 0
        for b in bits:
            mask |= int(b)
        self.write_reg("CTRL", mask)

    # --- identity / config / run control ---

    def check_identity(self) -> None:
        """Raise if MAGIC / VERSION do not match the frozen map revision."""
        magic = self.read_reg("MAGIC")
        version = self.read_reg("VERSION")
        if magic != MAGIC_RESET:
            raise RuntimeError(
                f"unexpected MAGIC 0x{magic:08X} (want 0x{MAGIC_RESET:08X})"
            )
        if version != VERSION_RESET:
            raise RuntimeError(
                f"unexpected VERSION 0x{version:08X} (want 0x{VERSION_RESET:08X})"
            )

    def soft_reset(self) -> None:
        self.pulse_ctrl(CtrlBits.SOFT_RST)

    def configure(self, config: ReadoutConfig) -> None:
        """Program PHASE_INC / PHASE0 / THRESHOLD / integrate window."""
        self.write_reg("PHASE_INC", config.phase_inc)
        self.write_reg("PHASE0", config.phase0)
        self.write_reg("THRESHOLD", config.threshold)
        self.write_reg("INTEGRATE_START", config.integrate_start)
        self.write_reg("INTEGRATE_LENGTH", config.integrate_length)

    def arm(self) -> None:
        """Pulse CTRL.ARM — clears DONE/OVERRUN; sets ARMED (per map)."""
        self.pulse_ctrl(CtrlBits.ARM)

    def clear_done(self) -> None:
        self.pulse_ctrl(CtrlBits.CLR_DONE)

    # --- sample push ---

    def push_iq_q1_14(
        self, i_samples: Sequence[int], q_samples: Sequence[int]
    ) -> None:
        """Pack signed Q1.14 I/Q and push as AXIS/DMA words."""
        self.push_axis_words(pack_iq_words(i_samples, q_samples))

    def push_axis_words(self, words: Sequence[int]) -> None:
        """Push already-packed ``{Q,I}`` uint32 beats (TLAST implied at end)."""
        self._be.push_axis_words(words)

    # --- status / results ---

    def read_status(self) -> StatusBits:
        return StatusBits(self.read_reg("STATUS"))

    def is_done(self) -> bool:
        return bool(self.read_status() & StatusBits.DONE)

    def read_results(self) -> ReadoutResult:
        return ReadoutResult(
            result_i=_as_signed32(self.read_reg("RESULT_I")),
            result_q=_as_signed32(self.read_reg("RESULT_Q")),
            result_meta=self.read_reg("RESULT_META"),
            status=self.read_reg("STATUS"),
            if_sample_count=self.read_reg("IF_SAMPLE_COUNT"),
        )

    def run_acquisition(
        self,
        config: ReadoutConfig,
        i_samples: Sequence[int],
        q_samples: Sequence[int],
        *,
        soft_reset_first: bool = False,
    ) -> None:
        """Configure → ARM → push IF samples. Does not wait for DONE.

        On a mock backend, call ``MockBackend.inject_results`` (or a board-side
        wait) before ``read_results``.
        """
        if soft_reset_first:
            self.soft_reset()
        self.configure(config)
        self.arm()
        self.push_iq_q1_14(i_samples, q_samples)


def _as_signed32(u: int) -> int:
    u &= 0xFFFF_FFFF
    return u - 0x1_0000_0000 if u >= 0x8000_0000 else u
