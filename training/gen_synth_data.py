"""Generate synthetic rPPG training traces when no real dataset is available.

Produces .npz files matching train.py's contract:
  trace   [N, 3, 240] float32  raw (unnormalized) mean-ROI traces, 8 s @ 30 Hz
  bpm     [N]         float32  ground-truth HR
  tone    [N]         int      Monk skin tone 1-10 (equity sampling)
  subject [N]         int      subject id (subject-wise train/val split)

These are physiologically-shaped synthetic signals: a pulsatile fundamental
plus harmonics at the target HR, respiration amplitude-modulation, baseline
wander, tone-dependent SNR (darker tones get a weaker pulsatile signal, as in
real rPPG), and occasional motion bursts. A model trained on these genuinely
learns trace -> HR (a frequency-estimation task) and runs in the app; it is NOT
a substitute for validation on real rPPG datasets before relying on accuracy.

Usage:
  python gen_synth_data.py --out ./data --subjects 80 --windows 120
"""

import argparse
import os

import numpy as np

FS = 30.0          # Hz
T = 240            # samples (8 s)
HARMONICS = [(1.0, 1.0), (2.0, 0.4), (3.0, 0.15)]  # (freq mult, amplitude)


def tone_snr_scale(tone: int) -> float:
    """Pulsatile amplitude scale by Monk tone: ~1.0 at tone 1, ~0.45 at tone
    10. Mirrors the real-world drop in green-channel SNR for darker skin."""
    return float(np.interp(tone, [1, 10], [1.0, 0.45]))


def make_window(rng: np.random.Generator, hr_bpm: float, tone: int,
                subject_dc: np.ndarray) -> np.ndarray:
    """One [3, 240] raw trace. Channel 0 = dominant (green-remapped) pulsatile;
    channels 1,2 weaker and noisier."""
    t = np.arange(T) / FS
    f = hr_bpm / 60.0
    phase = rng.uniform(0, 2 * np.pi)

    # Pulsatile fundamental + harmonics.
    pulse = np.zeros(T, dtype=np.float64)
    for mult, amp in HARMONICS:
        pulse += amp * np.sin(2 * np.pi * f * mult * t + phase)

    # Respiration amplitude modulation (0.15-0.35 Hz).
    resp_f = rng.uniform(0.15, 0.35)
    resp = 1.0 + 0.12 * np.sin(2 * np.pi * resp_f * t + rng.uniform(0, 2 * np.pi))
    pulse = pulse * resp

    # Baseline wander: slow drift + linear trend.
    wander_f = rng.uniform(0.05, 0.25)
    wander = 0.6 * np.sin(2 * np.pi * wander_f * t + rng.uniform(0, 2 * np.pi))
    wander += np.linspace(0, rng.uniform(-0.4, 0.4), T)

    amp = tone_snr_scale(tone)
    # SNR varies window-to-window so the confidence head sees easy and hard
    # examples (and learns to flag the hard ones).
    noise_sd = rng.uniform(0.05, 0.6) / max(amp, 0.3)

    channels = np.zeros((3, T), dtype=np.float64)
    # Per-channel pulsatile strength: ch0 strongest (green-remapped), r/b weaker.
    chan_gain = [1.0, rng.uniform(0.3, 0.6), rng.uniform(0.2, 0.45)]
    for c in range(3):
        sig = amp * chan_gain[c] * pulse + wander + subject_dc[c]
        sig = sig + rng.normal(0, noise_sd, T)
        # Occasional motion burst on ~15% of windows.
        if rng.random() < 0.15:
            start = rng.integers(0, T - 30)
            sig[start:start + rng.integers(5, 30)] += rng.normal(0, 1.5, 1)
        channels[c] = sig
    return channels.astype(np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="./data")
    ap.add_argument("--subjects", type=int, default=80)
    ap.add_argument("--windows", type=int, default=120, help="windows per subject")
    ap.add_argument("--seed", type=int, default=20260626)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    rng = np.random.default_rng(args.seed)

    # Tone distribution: ensure >= 1/3 dark (7-10) so equity sampling engages.
    tones_pool = np.array([1, 2, 3, 4, 5, 6] + [7, 8, 9, 10] * 2)

    for s in range(args.subjects):
        tone = int(rng.choice(tones_pool))
        subject_dc = rng.uniform(-2, 2, size=3)        # per-subject DC offset
        # Each subject sits in an HR band, with window-to-window variation.
        hr_center = rng.uniform(55, 110)
        traces, bpms = [], []
        for _ in range(args.windows):
            hr = float(np.clip(rng.normal(hr_center, 12), 45, 180))
            # A minority of windows are resting/elevated extremes.
            if rng.random() < 0.1:
                hr = float(rng.uniform(45, 180))
            traces.append(make_window(rng, hr, tone, subject_dc))
            bpms.append(hr)
        np.savez(
            os.path.join(args.out, f"subject_{s:03d}.npz"),
            trace=np.stack(traces),
            bpm=np.array(bpms, dtype=np.float32),
            tone=np.full(args.windows, tone, dtype=int),
            subject=np.full(args.windows, s, dtype=int),
        )
    total = args.subjects * args.windows
    print(f"wrote {args.subjects} subjects x {args.windows} = {total} windows to {args.out}")


if __name__ == "__main__":
    main()
