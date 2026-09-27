"""Golden-reference software DSP (DDC/FIR/decimate/integrate/threshold)."""

from cryocontrol.dsp_ref.ddc import ddc
from cryocontrol.dsp_ref.decimate import decimate
from cryocontrol.dsp_ref.fir import apply_fir, design_fir_lowpass
from cryocontrol.dsp_ref.integrate import integrate
from cryocontrol.dsp_ref.pipeline import (
    PipelineConfig,
    run_readout,
    synthesize_if_tone,
)
from cryocontrol.dsp_ref.threshold import discriminate

__all__ = [
    "ddc",
    "design_fir_lowpass",
    "apply_fir",
    "decimate",
    "integrate",
    "discriminate",
    "PipelineConfig",
    "run_readout",
    "synthesize_if_tone",
]
