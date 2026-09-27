"""Checked-in golden I/O vectors for Phase 2 / Phase 3 HDL replay.

Fixture contract
----------------
Each ``.npz`` file stores the readout-chain **input** (IF IQ stream) and
**outputs** (integrated I/Q + state decision), plus the pipeline parameters
needed to replay the chain bit-exact / within fixed-point tolerance in HDL.

``noiseless.npz``
  - ``input_iq_s0``, ``input_iq_s1`` : complex128 IF streams
  - ``output_iq_s0``, ``output_iq_s1`` : complex128 integrated IQ
  - ``decision_s0``, ``decision_s1`` : int64 state decisions (expect 0, 1)
  - shared config keys listed below

``noisy.npz``
  - ``input_iq`` : complex128 IF stream with AWGN
  - ``output_iq`` : complex128 integrated IQ
  - ``decision`` : int64 pipeline decision
  - ``true_state`` : int64 ground-truth qubit state
  - ``noise_sigma`` : float64 AWGN amplitude std used to build the input
  - shared config keys listed below

Shared config keys (both files)
  ``fs``, ``f_lo``, ``phase0``, ``fir_num_taps``, ``fir_cutoff``, ``fir_coeffs``,
  ``decim_factor``, ``integrate_start``, ``integrate_length`` (−1 means through
  end), ``threshold``, ``f_probe``, ``f0``, ``q``, ``coupling``, ``chi``,
  ``n_samples``.

Regenerate with::

    python -m cryocontrol.dsp_ref.fixtures.generate
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

FIXTURES_DIR = Path(__file__).resolve().parent

__all__ = ["FIXTURES_DIR", "load_fixture"]


def load_fixture(path: Path | str) -> np.lib.npyio.NpzFile:
    """Load a golden fixture ``.npz`` as a numpy ``NpzFile`` mapping."""
    return np.load(Path(path))
