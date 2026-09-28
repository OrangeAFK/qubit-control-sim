"""AXI-Stream IF sample packing (ARCHITECTURE.md §3.3.1).

Beat layout (little-endian ARM / PS buffer view)::

    TDATA[31:0] = {Q[15:0], I[15:0]}
    w = (uint16_t)I_q114 | ((uint32_t)(uint16_t)Q_q114 << 16)

Each lane is signed Q1.14 (two's complement in 16 bits).
"""

from __future__ import annotations

from typing import Iterable, List, Sequence, Tuple

# Q1.14: 1 sign/int bit + 14 fraction bits; representable ≈ [-2, 2).
Q1_14_FRAC_BITS: int = 14
Q1_14_SCALE: int = 1 << Q1_14_FRAC_BITS
Q1_14_MIN: int = -(1 << 15)
Q1_14_MAX: int = (1 << 15) - 1


def _to_u16(signed16: int) -> int:
    """Clamp-check then reinterpret signed 16-bit as unsigned 16-bit lane."""
    if signed16 < Q1_14_MIN or signed16 > Q1_14_MAX:
        raise ValueError(f"Q1.14 lane out of int16 range: {signed16}")
    return signed16 & 0xFFFF


def pack_iq_word(i_q114: int, q_q114: int) -> int:
    """Pack one complex IF sample into a 32-bit AXIS / DMA word."""
    return _to_u16(i_q114) | (_to_u16(q_q114) << 16)


def unpack_iq_word(word: int) -> Tuple[int, int]:
    """Unpack a packed AXIS word to signed Q1.14 (I, Q)."""
    w = word & 0xFFFF_FFFF
    i = w & 0xFFFF
    q = (w >> 16) & 0xFFFF
    if i >= 0x8000:
        i -= 0x10000
    if q >= 0x8000:
        q -= 0x10000
    return i, q


def pack_iq_words(i_samples: Sequence[int], q_samples: Sequence[int]) -> List[int]:
    """Pack parallel I/Q Q1.14 sequences into contiguous uint32 words."""
    if len(i_samples) != len(q_samples):
        raise ValueError(
            f"I/Q length mismatch: {len(i_samples)} vs {len(q_samples)}"
        )
    return [pack_iq_word(i, q) for i, q in zip(i_samples, q_samples)]


def pack_iq_bytes(i_samples: Sequence[int], q_samples: Sequence[int]) -> bytes:
    """Little-endian byte buffer ready for DMA MM2S (N * 4 bytes)."""
    return b"".join(w.to_bytes(4, "little") for w in pack_iq_words(i_samples, q_samples))


def float_to_q1_14(x: float) -> int:
    """Quantize a float to signed Q1.14 with round-to-nearest and saturate."""
    v = int(round(x * Q1_14_SCALE))
    if v < Q1_14_MIN:
        return Q1_14_MIN
    if v > Q1_14_MAX:
        return Q1_14_MAX
    return v


def q1_14_to_float(v: int) -> float:
    """Convert signed Q1.14 integer to float."""
    return float(v) / Q1_14_SCALE


def iter_words_from_bytes(buf: bytes | bytearray) -> Iterable[int]:
    """Yield little-endian uint32 words from a DMA buffer."""
    if len(buf) % 4 != 0:
        raise ValueError(f"buffer length {len(buf)} is not a multiple of 4")
    for i in range(0, len(buf), 4):
        yield int.from_bytes(buf[i : i + 4], "little")
