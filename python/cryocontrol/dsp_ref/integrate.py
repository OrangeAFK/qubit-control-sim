"""Integration / accumulation window for the software readout chain."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike


def integrate(
    samples: ArrayLike,
    *,
    start: int = 0,
    length: int | None = None,
) -> complex:
    """Accumulate samples over a contiguous window (complex sum).

    Parameters
    ----------
    samples :
        Input stream (real or complex).
    start :
        Inclusive start index of the accumulation window.
    length :
        Number of samples to accumulate. ``None`` means through the end.
    """
    x = np.asarray(samples)
    n = x.size
    if length is None:
        length = n - start
    stop = start + length
    if start < 0 or length < 1 or stop > n:
        raise ValueError(
            f"window [{start}:{stop}) is out of range for length-{n} samples"
        )
    return complex(np.sum(x[start:stop]))
