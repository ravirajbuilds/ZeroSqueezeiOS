"""Generate synthetic seismocardiography (SCG) training traces when no real
dataset is available.

Produces .npz files matching train_scg.py's contract:
  envelope [N, 1, 600] float32  raw (unnormalized) accel-magnitude traces, 6 s @ 100 Hz
  bpm      [N]         float32  ground-truth HR
  subject  [N]         int      subject id (subject-wise train/val split)

Physiologically-shaped synthetic SCG: per beat, an AO (aortic-valve opening)
complex modelled as a damped high-frequency burst, followed after the ejection
time (LVET) by a smaller AC (aortic-valve closing) burst, all amplitude-
modulated by respiration, riding on baseline wander, with per-subject SNR and
occasional motion bursts. A model trained on these genuinely learns
envelope -> HR (a frequency/morphology task) and runs in the app; it is NOT a
substitute for validation on real chest-SCG recordings (e.g. PhysioNet CEBS)
before relying on accuracy.

Usage:
  python gen_synth_scg.py --out ./scg_data --subjects 80 --windows 120
"""

import argparse
import os

import numpy as np

FS = 100.0        # Hz
T = 600           # samples (6 s)


def damped_burst(n: int, freq: float, decay: float) -> np.ndarray:
    """A short damped sinusoid — one valve-motion complex."""
    t = np.arange(n) / FS
    return np.exp(-t / decay) * np.sin(2 * np.pi * freq * t)


def synth_window(bpm: float, rng: np.random.Generator, snr: float) -> np.ndarray:
    period = 60.0 / bpm
    period_samp = period * FS
    sig = np.zeros(T, dtype=np.float64)

    # Weissler rate-corrected ejection time (ms) + small jitter -> AC offset.
    lvet_ms = 416.0 - 1.7 * bpm + rng.normal(0, 8)
    lvet_samp = int(np.clip(lvet_ms, 180, 420) / 1000.0 * FS)

    ao_len = int(0.06 * FS)   # 60 ms AO complex
    ac_len = int(0.05 * FS)   # 50 ms AC complex
    ao = damped_burst(ao_len, freq=rng.uniform(25, 35), decay=0.012)
    ac = 0.45 * damped_burst(ac_len, freq=rng.uniform(20, 30), decay=0.012)

    # Beat onsets with small interval variability (HRV).
    t0 = rng.uniform(0, period_samp)
    onset = t0
    while onset < T:
        i = int(onset)
        amp = 1.0 + rng.normal(0, 0.08)          # beat-to-beat amplitude jitter
        if i + ao_len < T:
            sig[i:i + ao_len] += amp * ao
        j = i + lvet_samp
        if 0 <= j and j + ac_len < T:
            sig[j:j + ac_len] += amp * ac
        onset += period_samp * (1.0 + rng.normal(0, 0.03))

    # Respiration amplitude modulation (0.2-0.35 Hz) + baseline wander.
    t = np.arange(T) / FS
    resp_hz = rng.uniform(0.2, 0.35)
    sig *= 1.0 + 0.15 * np.sin(2 * np.pi * resp_hz * t + rng.uniform(0, 6.28))
    sig += 0.05 * np.sin(2 * np.pi * rng.uniform(0.05, 0.15) * t)   # wander

    # Sensor + body noise scaled to the requested SNR.
    sig += rng.normal(0, np.std(sig) / max(snr, 1e-3), T)

    # Occasional motion burst (10% of windows) — a brief broadband transient.
    if rng.random() < 0.1:
        s = rng.integers(0, T - 30)
        sig[s:s + 30] += rng.normal(0, 0.5, 30)

    # Return as a positive-offset "magnitude" trace, matching the app's
    # vector-magnitude input (the app detrends internally, training
    # standardizes — so the DC offset is irrelevant but kept realistic).
    return np.abs(sig) + 1.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="scg_data")
    ap.add_argument("--subjects", type=int, default=80)
    ap.add_argument("--windows", type=int, default=120)
    ap.add_argument("--seed", type=int, default=11)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    rng = np.random.default_rng(args.seed)

    for sid in range(args.subjects):
        snr = rng.uniform(2.5, 9.0)               # per-subject signal strength
        env = np.zeros((args.windows, 1, T), dtype=np.float32)
        bpm = np.zeros(args.windows, dtype=np.float32)
        for w in range(args.windows):
            hr = rng.uniform(45, 150)
            env[w, 0] = synth_window(hr, rng, snr).astype(np.float32)
            bpm[w] = hr
        subject = np.full(args.windows, sid, dtype=int)
        np.savez(
            os.path.join(args.out, f"subject_{sid:03d}.npz"),
            envelope=env, bpm=bpm, subject=subject,
        )
    print(f"wrote {args.subjects} subjects x {args.windows} windows -> {args.out}/")


if __name__ == "__main__":
    main()
