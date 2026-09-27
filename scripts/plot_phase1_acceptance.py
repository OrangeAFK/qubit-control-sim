"""Generate Phase 1 acceptance plots into docs/.

Produces:
  docs/phase1_s21_two_state.png  — |S21(f)| for qubit |0> and |1>
  docs/phase1_fault_gain_drift.png — cryo-chain output before/after gain-drift fault
"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from cryocontrol.models.cryo_chain import CryoChain, CryoStage, FaultConfig
from cryocontrol.models.resonator import s21_for_state

DOCS = Path(__file__).resolve().parents[1] / "docs"

F0 = 6.0e9
Q = 1.0e4
COUPLING = 0.8
CHI = 5.0e6


def plot_two_state_s21(path: Path) -> None:
    f = np.linspace(F0 - 8 * F0 / Q, F0 + CHI + 8 * F0 / Q, 4001)
    mag0 = np.abs(s21_for_state(f, f0=F0, q=Q, coupling=COUPLING, state=0, chi=CHI))
    mag1 = np.abs(s21_for_state(f, f0=F0, q=Q, coupling=COUPLING, state=1, chi=CHI))

    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.plot((f - F0) / 1e6, mag0, label=r"$|0\rangle$ ($f_0$)")
    ax.plot((f - F0) / 1e6, mag1, label=rf"$|1\rangle$ ($f_0+\chi$, $\chi={CHI/1e6:.0f}$ MHz)")
    ax.axvline(0.0, color="gray", ls=":", lw=1)
    ax.axvline(CHI / 1e6, color="gray", ls=":", lw=1)
    ax.set_xlabel(r"Detuning from $f_0$ (MHz)")
    ax.set_ylabel(r"$|S_{21}(f)|$")
    ax.set_title("Phase 1: two-state resonator spectroscopy")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def plot_gain_drift_fault(path: Path) -> None:
    stages = [
        CryoStage(
            name="amp",
            temperature=4.0,
            attenuation_db=0.0,
            amp_gain_db=20.0,
            noise_temperature=0.0,
            cable_loss_db=0.0,
        )
    ]
    # Probe a unitary IQ tone through the chain (before/after gain drift).
    t = np.linspace(0.0, 1e-6, 500)
    signal = np.exp(2j * np.pi * 10e6 * t)

    before = CryoChain(stages).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))
    after = CryoChain(
        stages,
        faults=FaultConfig(gain_drift_db=-6.0, gain_drift_enabled=True),
    ).apply(signal, bandwidth=1e6, rng=np.random.default_rng(0))

    fig, axes = plt.subplots(2, 1, figsize=(8, 5.5), sharex=True)
    axes[0].plot(t * 1e9, before.real, label="I before")
    axes[0].plot(t * 1e9, after.real, label="I after (−6 dB gain drift)", ls="--")
    axes[0].set_ylabel("I (a.u.)")
    axes[0].set_title("Phase 1: gain-drift fault injection (before / after)")
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)

    axes[1].plot(t * 1e9, np.abs(before), label="|IQ| before")
    axes[1].plot(t * 1e9, np.abs(after), label="|IQ| after", ls="--")
    axes[1].set_xlabel("Time (ns)")
    axes[1].set_ylabel("|IQ| (a.u.)")
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main() -> None:
    DOCS.mkdir(parents=True, exist_ok=True)
    two_state = DOCS / "phase1_s21_two_state.png"
    fault = DOCS / "phase1_fault_gain_drift.png"
    plot_two_state_s21(two_state)
    plot_gain_drift_fault(fault)
    print(f"Wrote {two_state}")
    print(f"Wrote {fault}")


if __name__ == "__main__":
    main()
