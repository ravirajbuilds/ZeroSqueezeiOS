"""Sanity-check a converted ZSHR.mlpackage: feed clean synthetic pulsatile
traces at known heart rates and confirm the model recovers them.

Standardizes input exactly like the app's CoreMLHeartRateModel.traceTensor.

Usage:
  python validate_coreml.py ZSHR.mlpackage
"""

import sys

import numpy as np
import coremltools as ct

FS = 30.0
T = 240


def clean_trace(hr_bpm: float) -> np.ndarray:
    t = np.arange(T) / FS
    f = hr_bpm / 60.0
    pulse = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t)
    ch = np.stack([pulse, 0.5 * pulse, 0.35 * pulse]).astype(np.float32)
    # Per-channel standardize (mirror the app).
    mean = ch.mean(axis=-1, keepdims=True)
    std = np.maximum(ch.std(axis=-1, keepdims=True), 1e-6)
    return ((ch - mean) / std).reshape(1, 3, T).astype(np.float32)


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    model = ct.models.MLModel(sys.argv[1])
    print(f"{'true':>6} {'pred':>7} {'conf':>6} {'err':>6}")
    errs = []
    for hr in [50, 60, 72, 88, 100, 120, 150]:
        out = model.predict({"trace": clean_trace(hr)})
        bpm = float(np.array(out["bpm"]).reshape(-1)[0])
        conf = float(np.array(out["confidence"]).reshape(-1)[0])
        err = abs(bpm - hr)
        errs.append(err)
        print(f"{hr:6d} {bpm:7.1f} {conf:6.2f} {err:6.1f}")
    mae = float(np.mean(errs))
    print(f"\nMAE on clean sinusoids: {mae:.2f} bpm")
    if mae > 8:
        raise SystemExit(f"FAIL: MAE {mae:.2f} bpm exceeds 8 bpm sanity gate")
    print("PASS")


if __name__ == "__main__":
    main()
