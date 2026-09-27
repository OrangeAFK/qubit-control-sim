"""Integer-factor decimation (keep-every-Mth sample after anti-alias FIR)."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def decimate(samples: ArrayLike, factor: int) -> NDArray:
    """Downsample by an integer factor without filtering.

    Anti-alias low-pass filtering is the caller's responsibility (see
    ``design_fir_lowpass`` / ``apply_fir``). This step is the HDL-equivalent
    of taking every ``factor``-th sample starting at index 0.

    Parameters
    ----------
    samples :
        Input sample stream (real or complex).
    factor :
        Decimation factor M >= 1. Output is ``samples[::factor]``.
    """
    if not isinstance(factor, (int, np.integer)) or int(factor) < 1:
        raise ValueError(f"factor must be an integer >= 1, got {factor!r}")
    x = np.asarray(samples)
    return x[:: int(factor)]
