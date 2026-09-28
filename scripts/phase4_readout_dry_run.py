#!/usr/bin/env python3
"""Phase 4 readout dry-run: MockBackend + fixture golden compare (no board).

Exercises ReadoutDriver configure → push → RESULT_* compare against Phase 2/3
fixtures. Injects quantized golden integrated IQ (MockBackend does not run DSP).

This does NOT claim the Cora ran, does NOT load a bitstream, and does NOT satisfy
Phase 4 on-hardware acceptance.
"""

from __future__ import annotations

import argparse
import sys
from typing import Sequence, Tuple

import numpy as np

from cryocontrol.dsp_ref.fixtures import FIXTURES_DIR, load_fixture
from cryocontrol.hardware.driver import ReadoutConfig, ReadoutDriver
from cryocontrol.hardware.mock_backend import MockBackend
from cryocontrol.hardware.packing import float_to_q1_14

# Chain-wide tolerance from docs/fixed_point_notes.md (float integrated IQ).
IQ_ABS_TOL: float = 1.0
Q12_14_SCALE: float = float(1 << 14)


def _complex_to_q1_14(iq: np.ndarray) -> Tuple[list[int], list[int]]:
    i = [float_to_q1_14(float(z.real)) for z in iq]
    q = [float_to_q1_14(float(z.imag)) for z in iq]
    return i, q


def _float_to_q12_14(x: float) -> int:
    return int(round(x * Q12_14_SCALE))


def _q12_14_to_float(v: int) -> float:
    return float(v) / Q12_14_SCALE


def _run_case(
    label: str,
    input_iq: np.ndarray,
    output_iq: complex,
    decision: int,
    *,
    iq_tol: float,
) -> bool:
    """Push fixture IF via mock driver; inject golden RESULT_*; compare."""
    be = MockBackend()
    drv = ReadoutDriver(be)
    drv.check_identity()

    i_s, q_s = _complex_to_q1_14(np.asarray(input_iq))
    drv.run_acquisition(ReadoutConfig(), i_s, q_s)

    golden_i = _float_to_q12_14(float(np.real(output_iq)))
    golden_q = _float_to_q12_14(float(np.imag(output_iq)))
    be.inject_results(
        golden_i,
        golden_q,
        decision=bool(decision),
        if_sample_count=len(i_s),
    )

    res = drv.read_results()
    err_i = abs(_q12_14_to_float(res.result_i) - float(np.real(output_iq)))
    err_q = abs(_q12_14_to_float(res.result_q) - float(np.imag(output_iq)))
    decision_ok = int(res.decision) == int(decision)
    iq_ok = err_i <= iq_tol and err_q <= iq_tol
    ok = iq_ok and decision_ok and res.done

    print(
        f"[{label}] samples={len(i_s)} "
        f"err_I={err_i:.6g} err_Q={err_q:.6g} tol={iq_tol} "
        f"decision={int(res.decision)} (want {int(decision)}) "
        f"{'PASS' if ok else 'FAIL'}"
    )
    if not ok:
        print(
            f"  RESULT_I=0x{res.result_i & 0xFFFFFFFF:08X} "
            f"RESULT_Q=0x{res.result_q & 0xFFFFFFFF:08X} "
            f"meta=0x{res.result_meta:08X} status=0x{res.status:08X}"
        )
    return ok


def main(argv: Sequence[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--iq-tol",
        type=float,
        default=IQ_ABS_TOL,
        help="absolute tolerance on integrated I/Q (float units)",
    )
    args = p.parse_args(list(argv) if argv is not None else None)

    print(
        "phase4_readout_dry_run: MockBackend only — NOT on-hardware, "
        "NOT a Cora bring-up result."
    )

    noiseless = load_fixture(FIXTURES_DIR / "noiseless.npz")
    noisy = load_fixture(FIXTURES_DIR / "noisy.npz")

    cases_ok = [
        _run_case(
            "noiseless_s0",
            noiseless["input_iq_s0"],
            complex(noiseless["output_iq_s0"]),
            int(noiseless["decision_s0"]),
            iq_tol=args.iq_tol,
        ),
        _run_case(
            "noiseless_s1",
            noiseless["input_iq_s1"],
            complex(noiseless["output_iq_s1"]),
            int(noiseless["decision_s1"]),
            iq_tol=args.iq_tol,
        ),
        _run_case(
            "noisy",
            noisy["input_iq"],
            complex(noisy["output_iq"]),
            int(noisy["decision"]),
            iq_tol=args.iq_tol,
        ),
    ]

    if all(cases_ok):
        print("All dry-run cases passed (software path only).")
        return 0
    print("One or more dry-run cases failed.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
