"""Tests for checked-in Phase 2 golden DSP fixtures."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from cryocontrol.dsp_ref.fir import design_fir_lowpass
from cryocontrol.dsp_ref.fixtures import FIXTURES_DIR, load_fixture
from cryocontrol.dsp_ref.pipeline import PipelineConfig, run_readout

NOISELESS = FIXTURES_DIR / "noiseless.npz"
NOISY = FIXTURES_DIR / "noisy.npz"


def test_fixture_files_exist() -> None:
    """Golden noiseless + noisy fixture files are checked into the repo."""
    assert NOISELESS.is_file(), f"missing {NOISELESS}"
    assert NOISY.is_file(), f"missing {NOISY}"


def test_noiseless_fixture_loadable_and_matches_pipeline() -> None:
    """Noiseless fixture I/O replays through run_readout to the recorded outputs."""
    data = load_fixture(NOISELESS)
    cfg = PipelineConfig(
        fs=float(data["fs"]),
        f_lo=float(data["f_lo"]),
        fir_num_taps=int(data["fir_num_taps"]),
        fir_cutoff=float(data["fir_cutoff"]),
        decim_factor=int(data["decim_factor"]),
        integrate_start=int(data["integrate_start"]),
        integrate_length=(
            None
            if data["integrate_length"] < 0
            else int(data["integrate_length"])
        ),
        threshold=float(data["threshold"]),
        phase0=float(data["phase0"]),
    )
    np.testing.assert_allclose(
        design_fir_lowpass(cfg.fir_num_taps, cfg.fir_cutoff, cfg.fs),
        data["fir_coeffs"],
        rtol=0, atol=0,
    )

    for state in (0, 1):
        iq, decision = run_readout(data[f"input_iq_s{state}"], cfg)
        assert decision == int(data[f"decision_s{state}"])
        assert decision == state
        assert iq == pytest.approx(complex(data[f"output_iq_s{state}"]), rel=0, abs=1e-12)


def test_noisy_fixture_loadable_and_matches_pipeline() -> None:
    """Noisy fixture I/O is loadable and matches a fresh pipeline run."""
    data = load_fixture(NOISY)
    cfg = PipelineConfig(
        fs=float(data["fs"]),
        f_lo=float(data["f_lo"]),
        fir_num_taps=int(data["fir_num_taps"]),
        fir_cutoff=float(data["fir_cutoff"]),
        decim_factor=int(data["decim_factor"]),
        integrate_start=int(data["integrate_start"]),
        integrate_length=(
            None
            if data["integrate_length"] < 0
            else int(data["integrate_length"])
        ),
        threshold=float(data["threshold"]),
        phase0=float(data["phase0"]),
    )
    iq, decision = run_readout(data["input_iq"], cfg)
    assert decision == int(data["decision"])
    assert int(data["true_state"]) in (0, 1)
    assert iq == pytest.approx(complex(data["output_iq"]), rel=0, abs=1e-12)
