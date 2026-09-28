"""In-memory hardware backend for pytest (no board required)."""

from __future__ import annotations

from typing import Dict, List, Optional, Sequence

from cryocontrol.hardware.axi_lite_regs import (
    MAP_SIZE_BYTES,
    REGS,
    REG_BY_OFFSET,
    CtrlBits,
    StatusBits,
)


class MockBackend:
    """Simulates the Phase 4 Lite aperture + AXIS sample sink.

    Register resets match ``axi_lite_regs.REGS``. CTRL W1P bits update STATUS.
    Results are not computed here — tests call ``inject_results`` after push.
    """

    def __init__(self) -> None:
        self._regs: Dict[int, int] = {r.offset: r.reset & 0xFFFF_FFFF for r in REGS}
        self.axis_words: List[int] = []
        self._armed_for_push: bool = False

    def write_u32(self, offset: int, value: int) -> None:
        self._check_offset(offset)
        reg = REG_BY_OFFSET.get(offset)
        if reg is None:
            # Reserved hole — ignore (matches "not implemented" Lite space).
            return
        if reg.access == "ro":
            return
        value &= 0xFFFF_FFFF
        if offset == 0x00:  # CTRL — write-1-to-pulse; readable as 0
            self._apply_ctrl(value)
            self._regs[offset] = 0
        else:
            self._regs[offset] = value

    def read_u32(self, offset: int) -> int:
        self._check_offset(offset)
        return self._regs.get(offset, 0) & 0xFFFF_FFFF

    def push_axis_words(self, words: Sequence[int]) -> None:
        packed = [int(w) & 0xFFFF_FFFF for w in words]
        self.axis_words.extend(packed)
        if self._armed_for_push or self._status_has(StatusBits.ARMED | StatusBits.BUSY):
            count = self._regs.get(0x38, 0) + len(packed)
            self._regs[0x38] = count & 0xFFFF_FFFF
            # Mark busy while samples arrive; DONE is set only via inject_results.
            self._set_status_bits(StatusBits.BUSY, True)
            self._set_status_bits(StatusBits.ARMED, True)
        else:
            self._set_status_bits(StatusBits.OVERRUN, True)

    def inject_results(
        self,
        result_i: int,
        result_q: int,
        *,
        decision: bool = False,
        if_sample_count: Optional[int] = None,
    ) -> None:
        """Latch acquisition results as the PL would after ``out_valid``."""
        self._regs[0x1C] = result_i & 0xFFFF_FFFF  # RESULT_I
        self._regs[0x20] = result_q & 0xFFFF_FFFF  # RESULT_Q
        self._regs[0x24] = 1 if decision else 0  # RESULT_META
        if if_sample_count is not None:
            self._regs[0x38] = if_sample_count & 0xFFFF_FFFF
        self._set_status_bits(StatusBits.DONE, True)
        self._set_status_bits(StatusBits.BUSY, False)
        self._set_status_bits(StatusBits.ARMED, False)
        self._armed_for_push = False

    def _apply_ctrl(self, value: int) -> None:
        if value & CtrlBits.SOFT_RST:
            self._soft_reset_datapath()
        if value & CtrlBits.ARM:
            self._set_status_bits(StatusBits.DONE, False)
            self._set_status_bits(StatusBits.OVERRUN, False)
            self._set_status_bits(StatusBits.ARMED, True)
            self._set_status_bits(StatusBits.BUSY, False)
            self._regs[0x38] = 0  # IF_SAMPLE_COUNT cleared on arm (typical)
            self.axis_words.clear()
            self._armed_for_push = True
        if value & CtrlBits.CLR_DONE:
            self._set_status_bits(StatusBits.DONE, False)

    def _soft_reset_datapath(self) -> None:
        """Clear sticky status/results; retain config regs (ARCHITECTURE)."""
        for name, off in (
            ("STATUS", 0x04),
            ("RESULT_I", 0x1C),
            ("RESULT_Q", 0x20),
            ("RESULT_META", 0x24),
            ("IF_SAMPLE_COUNT", 0x38),
        ):
            reg = REG_BY_OFFSET[off]
            self._regs[off] = reg.reset & 0xFFFF_FFFF
        self.axis_words.clear()
        self._armed_for_push = False

    def _status_has(self, bits: StatusBits) -> bool:
        return bool(self._regs[0x04] & int(bits))

    def _set_status_bits(self, bits: StatusBits, set_on: bool) -> None:
        cur = self._regs[0x04]
        mask = int(bits)
        self._regs[0x04] = (cur | mask) if set_on else (cur & ~mask)
        self._regs[0x04] &= 0xFFFF_FFFF

    @staticmethod
    def _check_offset(offset: int) -> None:
        if offset < 0 or offset >= MAP_SIZE_BYTES or offset % 4 != 0:
            raise ValueError(f"invalid Lite offset 0x{offset:X}")
