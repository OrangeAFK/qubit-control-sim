"""Simple threshold-based state discrimination (refined in Phase 8)."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


def discriminate(
    iq: ArrayLike,
    threshold: float,
) -> int | NDArray[np.integer]:
    """Classify IQ by comparing ``Re(iq)`` to ``threshold``.

    Decision rule (Phase 2 simple classifier):
    - ``Re(iq) < threshold`` → state ``0``
    - ``Re(iq) >= threshold`` → state ``1``

    A scalar input returns a Python ``int``; an array returns an integer
    ``ndarray`` of the same shape.
    """
    z = np.asarray(iq)
    states = (np.real(z) >= threshold).astype(np.int64)
    if states.ndim == 0:
        return int(states)
    return states
