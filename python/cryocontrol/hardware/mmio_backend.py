"""MMIO / memory-mapped backend stub for later Cora Z7 bring-up.

Phase 4 software tests use ``MockBackend``. This module provides:

1. ``ByteBufferBackend`` — Lite aperture as a mutable byte buffer (unit-testable
   offset math; useful once a real mmap view is available).
2. ``MmioBackend`` — placeholder that documents the intended ``/dev/mem`` or UIO
   wiring and refuses to claim on-hardware success until mapped.
"""

from __future__ import annotations

from typing import Optional, Sequence, Union

from cryocontrol.hardware.axi_lite_regs import BASE_ADDR_TENTATIVE, MAP_SIZE_BYTES

MutableBytes = Union[bytearray, memoryview]


class ByteBufferBackend:
    """AXI-Lite over a little-endian byte buffer covering the primary aperture.

    Does not model W1P CTRL side effects or AXIS DMA — only raw 32-bit R/W at
    offsets. ``push_axis_words`` stores words for inspection (sim stand-in).
    """

    def __init__(self, mem: Optional[MutableBytes] = None) -> None:
        if mem is None:
            self._mem: MutableBytes = bytearray(MAP_SIZE_BYTES)
        else:
            if len(mem) < MAP_SIZE_BYTES:
                raise ValueError(
                    f"aperture buffer too small: {len(mem)} < {MAP_SIZE_BYTES}"
                )
            self._mem = mem
        self.axis_words: list[int] = []

    def write_u32(self, offset: int, value: int) -> None:
        self._check_offset(offset)
        raw = (value & 0xFFFF_FFFF).to_bytes(4, "little")
        self._mem[offset : offset + 4] = raw

    def read_u32(self, offset: int) -> int:
        self._check_offset(offset)
        return int.from_bytes(self._mem[offset : offset + 4], "little")

    def push_axis_words(self, words: Sequence[int]) -> None:
        self.axis_words.extend(int(w) & 0xFFFF_FFFF for w in words)

    @staticmethod
    def _check_offset(offset: int) -> None:
        if offset < 0 or offset + 4 > MAP_SIZE_BYTES or offset % 4 != 0:
            raise ValueError(f"invalid Lite offset 0x{offset:X}")


class MmioBackend:
    """Placeholder for physical Cora MMIO (``/dev/mem``, UIO, or PYNQ MMIO).

    Construction records the tentative base from ARCHITECTURE.md §3.3.1. Until a
    mapped view is supplied, all accessors raise ``NotImplementedError`` so
    callers cannot accidentally treat the stub as a live board.
    """

    def __init__(
        self,
        base_addr: int = BASE_ADDR_TENTATIVE,
        size: int = MAP_SIZE_BYTES,
        *,
        mapped: Optional[MutableBytes] = None,
    ) -> None:
        self.base_addr = base_addr
        self.size = size
        self._mapped = mapped
        self._buf: Optional[ByteBufferBackend] = (
            ByteBufferBackend(mapped) if mapped is not None else None
        )

    def write_u32(self, offset: int, value: int) -> None:
        self._require_mapped().write_u32(offset, value)

    def read_u32(self, offset: int) -> int:
        return self._require_mapped().read_u32(offset)

    def push_axis_words(self, words: Sequence[int]) -> None:
        """DMA MM2S path not wired yet — buffer locally when a map exists."""
        self._require_mapped().push_axis_words(words)

    def _require_mapped(self) -> ByteBufferBackend:
        if self._buf is None:
            raise NotImplementedError(
                "Cora MMIO not mapped; pass mapped=memoryview/... or use "
                f"MockBackend for sim (tentative base 0x{self.base_addr:08X})"
            )
        return self._buf
