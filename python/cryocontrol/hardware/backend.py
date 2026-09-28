"""Hardware backend protocol: AXI-Lite MMIO + AXIS/DMA sample feed.

Drivers talk only to a ``HardwareBackend``. Tests use ``MockBackend``; Cora
bring-up will plug in ``MmioBackend`` (or a UIO/mmap subclass) later.
"""

from __future__ import annotations

from typing import List, Protocol, Sequence, runtime_checkable


@runtime_checkable
class HardwareBackend(Protocol):
    """Minimal PS↔PL transport used by ``ReadoutDriver``."""

    def write_u32(self, offset: int, value: int) -> None:
        """Write a 32-bit word at a byte offset within the Lite aperture."""

    def read_u32(self, offset: int) -> int:
        """Read a 32-bit word at a byte offset within the Lite aperture."""

    def push_axis_words(self, words: Sequence[int]) -> None:
        """Feed packed IF samples (ARCHITECTURE §3.3.1) toward the Stream slave.

        On hardware this is typically: copy to DDR → cache-clean → DMA MM2S with
        ``TLAST`` on the final beat. Mock backends append to an in-memory buffer.
        """
