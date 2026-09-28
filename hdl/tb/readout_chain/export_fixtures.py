"""Export Phase 2 NPZ fixtures to ``$readmemh`` vectors for ``tb_readout_chain``.

Stimulus = quantized IF IQ from fixture ``input_iq_*`` (Q1.14).
Expected = fixture ``output_iq_*`` (Q12.14) and ``decision_*`` (1-bit),
cross-checked against ``dsp_ref.threshold.discriminate`` and a Q12.14
integer compare so HDL bit-exact decisions stay aligned with
``docs/fixed_point_notes.md`` § readout_chain.

Run from repo root (package importable)::

    python hdl/tb/readout_chain/export_fixtures.py

Writes under ``hdl/tb/readout_chain/vectors/``.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np

from cryocontrol.dsp_ref.fixtures import FIXTURES_DIR, load_fixture
from cryocontrol.dsp_ref.threshold import discriminate

FRAC_BITS = 14
SCALE = 1 << FRAC_BITS
# Chain-wide: abs error ≤ 1.0 in Q12.14 (docs/fixed_point_notes.md).
TOL_LSB = SCALE
# Signed Q12.14 lives in 26 bits; clip to that range before packing into 32-bit.
Q1214_MAX = (1 << 25) - 1
Q1214_MIN = -(1 << 25)

TB_DIR = Path(__file__).resolve().parent
VEC_DIR = TB_DIR / "vectors"
NOISELESS = FIXTURES_DIR / "noiseless.npz"
NOISY = FIXTURES_DIR / "noisy.npz"


def float_to_q114(x: np.ndarray) -> np.ndarray:
    """Round-nearest float → signed Q1.14 int16 codes."""
    v = np.rint(np.asarray(x, dtype=np.float64) * SCALE)
    return np.clip(v, -32768, 32767).astype(np.int16)


def float_to_q1214_scalar(x: float) -> int:
    """Round-nearest float → signed Q12.14 code (26-bit range)."""
    v = int(np.rint(float(x) * SCALE))
    return int(np.clip(v, Q1214_MIN, Q1214_MAX))


def q114_to_hex_lines(codes: np.ndarray) -> list[str]:
    """Two's-complement 16-bit hex, one sample per line (for ``$readmemh``)."""
    u = codes.astype(np.int16).view(np.uint16)
    return [f"{int(v):04x}" for v in u]


def q1214_to_hex_line(code: int) -> str:
    """Two's-complement 32-bit hex (sign-extended Q12.14) for ``$readmemh``."""
    return f"{code & 0xFFFFFFFF:08x}"


def write_mem16(path: Path, codes: np.ndarray) -> None:
    path.write_text("\n".join(q114_to_hex_lines(codes)) + "\n", encoding="utf-8")


def write_mem32_scalar(path: Path, code: int) -> None:
    path.write_text(q1214_to_hex_line(code) + "\n", encoding="utf-8")


def write_mem1_scalar(path: Path, bit: int) -> None:
    """Single 1-bit expected decision as one hex digit for ``$readmemh``."""
    if bit not in (0, 1):
        raise ValueError(f"decision must be 0 or 1, got {bit}")
    path.write_text(f"{bit:01x}\n", encoding="utf-8")


def phase_inc_word(fs: float, f_lo: float) -> int:
    """Unsigned 32-bit NCO tuning word: round(f_lo/fs * 2^32)."""
    return int(np.round(f_lo / fs * (1 << 32))) & 0xFFFFFFFF


def phase0_word(phase0_rad: float) -> int:
    """Unsigned 32-bit initial phase: round(phase0/(2π) * 2^32)."""
    return int(np.round(phase0_rad / (2.0 * np.pi) * (1 << 32))) & 0xFFFFFFFF


def resolve_integrate_length(n_decim: int, start: int, length_raw: int) -> int:
    """Fixture ``integrate_length`` of −1 means through end of the stream."""
    if length_raw < 0:
        return n_decim - start
    return int(length_raw)


def export_case(
    name: str,
    input_iq: np.ndarray,
    output_iq: complex,
    fixture_decision: int,
    threshold: float,
    threshold_q: int,
) -> dict:
    """Write in IF / exp integrated IQ + decision mem files; return metadata."""
    dec_float = discriminate(output_iq, threshold=threshold)
    assert isinstance(dec_float, int)
    if dec_float != int(fixture_decision):
        raise AssertionError(
            f"{name}: discriminate({output_iq!r}, {threshold})={dec_float} "
            f"!= fixture decision={fixture_decision}"
        )

    in_i = float_to_q114(np.real(input_iq))
    in_q = float_to_q114(np.imag(input_iq))
    exp_i = float_to_q1214_scalar(float(np.real(output_iq)))
    exp_q = float_to_q1214_scalar(float(np.imag(output_iq)))
    dec_q = 1 if exp_i >= threshold_q else 0
    if dec_q != int(fixture_decision):
        raise AssertionError(
            f"{name}: Q12.14 compare (i={exp_i} >= thr={threshold_q}) → {dec_q} "
            f"!= fixture decision={fixture_decision}"
        )

    write_mem16(VEC_DIR / f"{name}_in_i.mem", in_i)
    write_mem16(VEC_DIR / f"{name}_in_q.mem", in_q)
    write_mem32_scalar(VEC_DIR / f"{name}_exp_i.mem", exp_i)
    write_mem32_scalar(VEC_DIR / f"{name}_exp_q.mem", exp_q)
    write_mem1_scalar(VEC_DIR / f"{name}_exp_decision.mem", int(fixture_decision))

    return {
        "name": name,
        "n_samples": int(input_iq.size),
        "exp_i": exp_i,
        "exp_q": exp_q,
        "exp_decision": int(fixture_decision),
        "source_npz": None,
    }


def write_params_svh(
    cases: list[dict],
    *,
    phase_inc: int,
    phase0: int,
    threshold_q: int,
    num_taps: int,
    decim_m: int,
    integrate_start: int,
    integrate_length: int,
) -> None:
    """SystemVerilog header consumed by ``tb_readout_chain.sv``."""
    assert cases, "no cases"
    n = cases[0]["n_samples"]
    for c in cases:
        assert c["n_samples"] == n

    names = ", ".join(f'"{c["name"]}"' for c in cases)
    lines = [
        "// Auto-generated by export_fixtures.py -- do not edit by hand.",
        "// Source: python/cryocontrol/dsp_ref/fixtures/{noiseless,noisy}.npz",
        f"localparam int RC_N_SAMPLES         = {n};",
        f"localparam int RC_N_CASES           = {len(cases)};",
        f"localparam int RC_TOL_LSB           = {TOL_LSB};  // abs err <= 1.0 in Q12.14",
        f"localparam int RC_NUM_TAPS          = {num_taps};",
        f"localparam int RC_DECIM_M           = {decim_m};",
        f"localparam int RC_INTEGRATE_START   = {integrate_start};",
        f"localparam int RC_INTEGRATE_LENGTH  = {integrate_length};",
        f"localparam int RC_THRESHOLD_Q       = {threshold_q};  // Q12.14",
        f"localparam logic [31:0] RC_PHASE_INC = 32'h{phase_inc:08x};",
        f"localparam logic [31:0] RC_PHASE0    = 32'h{phase0:08x};",
        f"localparam string RC_CASE_NAMES [0:RC_N_CASES-1] = '{{{names}}};",
        "",
    ]
    (VEC_DIR / "readout_chain_params.svh").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def write_manifest(
    cases: list[dict],
    *,
    phase_inc: int,
    phase0: int,
    threshold: float,
    threshold_q: int,
    integrate_start: int,
    integrate_length: int,
) -> None:
    rows = [
        "# Readout-chain TB vectors -- regenerated from Phase 2 NPZ",
        "# stimulus = quantize_Q1.14(fixture input_iq_*)",
        "# expected  = quantize_Q12.14(fixture output_iq_*) + fixture decision_*",
        f"# Q12.14 tol_lsb={TOL_LSB} (abs err <= 1.0); decisions bit-exact",
        f"# threshold_float={threshold} threshold_q1214={threshold_q}",
        f"# phase_inc=0x{phase_inc:08x} phase0=0x{phase0:08x}",
        f"# integrate_start={integrate_start} integrate_length={integrate_length}",
        "# case n_samples exp_i exp_q exp_decision source",
    ]
    for c in cases:
        rows.append(
            f"{c['name']} {c['n_samples']} {c['exp_i']} {c['exp_q']} "
            f"{c['exp_decision']} {c['source_npz']}"
        )
    (VEC_DIR / "MANIFEST.txt").write_text("\n".join(rows) + "\n", encoding="utf-8")


def _repo_rel(path: Path) -> str:
    """Path relative to repo root when possible (portable MANIFEST)."""
    repo = TB_DIR.parents[2]  # hdl/tb/readout_chain -> repo
    try:
        return path.resolve().relative_to(repo.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def main() -> None:
    VEC_DIR.mkdir(parents=True, exist_ok=True)

    nl = load_fixture(NOISELESS)
    ny = load_fixture(NOISY)

    fs = float(nl["fs"])
    f_lo = float(nl["f_lo"])
    phase0 = float(nl["phase0"])
    threshold = float(nl["threshold"])
    num_taps = int(nl["fir_num_taps"])
    decim_m = int(nl["decim_factor"])
    integrate_start = int(nl["integrate_start"])
    # Decimated length after FIR: n_samples / M (fixtures use integer M).
    n_if = int(np.asarray(nl["input_iq_s0"]).size)
    n_decim = n_if // decim_m
    integrate_length = resolve_integrate_length(
        n_decim, integrate_start, int(nl["integrate_length"])
    )

    assert float(ny["fs"]) == fs and float(ny["f_lo"]) == f_lo
    assert float(ny["phase0"]) == phase0
    assert float(ny["threshold"]) == threshold
    assert int(ny["fir_num_taps"]) == num_taps
    assert int(ny["decim_factor"]) == decim_m
    assert int(ny["integrate_start"]) == integrate_start

    phase_inc = phase_inc_word(fs, f_lo)
    phase0_w = phase0_word(phase0)
    threshold_q = float_to_q1214_scalar(threshold)

    cases = [
        export_case(
            "noiseless_s0",
            np.asarray(nl["input_iq_s0"]),
            complex(nl["output_iq_s0"]),
            int(nl["decision_s0"]),
            threshold,
            threshold_q,
        ),
        export_case(
            "noiseless_s1",
            np.asarray(nl["input_iq_s1"]),
            complex(nl["output_iq_s1"]),
            int(nl["decision_s1"]),
            threshold,
            threshold_q,
        ),
        export_case(
            "noisy",
            np.asarray(ny["input_iq"]),
            complex(ny["output_iq"]),
            int(ny["decision"]),
            threshold,
            threshold_q,
        ),
    ]
    cases[0]["source_npz"] = _repo_rel(NOISELESS)
    cases[1]["source_npz"] = _repo_rel(NOISELESS)
    cases[2]["source_npz"] = _repo_rel(NOISY)

    write_params_svh(
        cases,
        phase_inc=phase_inc,
        phase0=phase0_w,
        threshold_q=threshold_q,
        num_taps=num_taps,
        decim_m=decim_m,
        integrate_start=integrate_start,
        integrate_length=integrate_length,
    )
    write_manifest(
        cases,
        phase_inc=phase_inc,
        phase0=phase0_w,
        threshold=threshold,
        threshold_q=threshold_q,
        integrate_start=integrate_start,
        integrate_length=integrate_length,
    )
    print(
        f"Wrote {len(cases)} cases ({cases[0]['n_samples']} IF samples each, "
        f"threshold_q={threshold_q}) -> {VEC_DIR}"
    )


if __name__ == "__main__":
    main()
