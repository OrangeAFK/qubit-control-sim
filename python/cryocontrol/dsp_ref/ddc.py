"""Software digital downconversion (DDC): mix IF samples with a reference NCO."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def ddc(
    samples: ArrayLike,
    fs: float,
    f_lo: float,
    *,
    phase0: float = 0.0,
) -> NDArray[np.complexfloating]:
    """Mix complex (or real) IF samples with a software NCO to baseband.

    Implements ``y[n] = x[n] * exp(-j * (2π * f_lo * n / fs + phase0))`` so a
    complex tone at ``f_lo`` lands at DC.

    Parameters
    ----------
    samples :
        IF sample stream. Complex arrays are treated as I/Q; real arrays are
        promoted to complex with Q = 0.
    fs :
        Sample rate in Hz.
    f_lo :
        Local-oscillator / NCO frequency in Hz.
    phase0 :
        Initial NCO phase in radians (default 0).
    """
    x = np.asarray(samples, dtype=np.complex128)
    n = np.arange(x.size, dtype=np.float64)
    nco = np.exp(-1j * (2.0 * np.pi * f_lo * n / fs + phase0))
    return x * nco
