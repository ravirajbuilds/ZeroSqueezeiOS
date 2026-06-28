# ZeroSqueeze HR model training

Offline pipeline that produces `ZSHR.mlpackage` — the learned
heart-rate backend the app's `CoreMLHeartRateModel` loads at runtime.
The app works without it (classic peak detector fallback); drop the
model in to upgrade accuracy, PHRM-style.

Inspired by Google's PHRM (passive heart rate monitoring via smartphone
camera): temporal-shift CNN family, confidence gating, equity-targeted
sampling across the Monk Skin Tone scale.

## Model contract (must match `CoreMLHeartRateModel.swift`)

| | |
|---|---|
| input `trace` | Float32 `[1, 3, 240]` — r/g/b mean-ROI traces, 8 s @ 30 Hz, per-channel standardized (zero mean, unit variance). Channel 0 carries the dominant pulsatile signal (green is remapped into slot 0 by the app for face captures). |
| output `bpm` | Float32 `[1]` |
| output `confidence` | Float32 `[1]` in [0, 1] |

## Setup

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Data

Trace tensors + ground-truth HR come from public rPPG datasets,
preprocessed with [rPPG-Toolbox](https://github.com/ubicomplab/rPPG-Toolbox):

- **UBFC-rPPG**, **PURE** — small, easy to obtain for research.
- **VIPL-HR**, **MMPD** — larger, more motion/lighting diversity; MMPD
  includes Fitzpatrick skin-tone labels.
- **PHRM dataset / PHRM-mini weights** (Google) — largest and most
  diverse, but **research-only with IRB approval, non-commercial**. Use
  for benchmarking, do not ship the weights.

> Check each dataset's license before any commercial use. For a
> shippable commercial model you will likely need your own collected,
> consented data.

Use rPPG-Toolbox to read videos and emit mean-RGB ROI traces, then
`train.py --data <dir>` over `.npz` files with arrays:
`trace` `[N, 3, 240]` (raw, unnormalized — train-time standardization
mirrors the app) and `bpm` `[N]`.

### Equity sampling

PHRM enforced ≥33% Monk tones 7–10. Do the same: pass per-sample tone
labels via the optional `tone` array in the `.npz` and `train.py`
oversamples to the `--min-dark-fraction` (default 0.33). Validate MAPE
stratified by tone bucket, not just overall.

## Train

```bash
python train.py --data ./data --epochs 50 --out checkpoints/
```

Loss = L1 on bpm + BCE on confidence, where the confidence target is
whether the bpm error < 5. That makes the confidence head a calibrated
self-assessment usable for PHRM-style gating in the app.

## Convert to Core ML

```bash
python convert_to_coreml.py checkpoints/best.pt ZSHR.mlpackage
```

## Ship into the app

1. Copy `ZSHR.mlpackage` into `ZeroSqueeze/Resources/`.
2. Add it to `project.yml` under the ZeroSqueeze target:
   ```yaml
   resources:
     - ZeroSqueeze/Resources/ZSHR.mlpackage
   ```
3. `xcodegen generate` and rebuild. Xcode compiles it to
   `ZSHR.mlmodelc`; `CoreMLHeartRateModel` picks it up
   automatically and the router starts preferring it.

## Validation gates before shipping a model

- MAPE < 10% overall on a held-out free-living split.
- MAPE < 10% within *every* Monk tone bucket (1–3, 4–6, 7–10).
- Confidence gating at the router threshold (0.5) must improve MAPE.
- Spot-check against the classic detector on synthetic sinusoids
  (the unit suite in `ZeroSqueezeTests/HeartRateModelTests.swift`).

---

# ZeroSqueeze SCG model training (`ZSCardiacSCG.mlpackage`)

The chest modality has the same pluggable backend design as PPG:
`SCGProcessor` (classic AO detector) always runs; a learned model upgrades
HR when bundled, gated by `SCGHeartRateModelRouter`.

## Model contract (must match `SCGHeartRateModel.swift`)

| | |
|---|---|
| input `envelope` | Float32 `[1, 1, 600]` — accelerometer vector-magnitude trace, trailing 6 s @ 100 Hz, standardized (zero mean, unit variance). |
| output `bpm` | Float32 `[1]` |
| output `confidence` | Float32 `[1]` in [0, 1] |

## Data

Ground-truth pairs come from simultaneous chest-SCG + ECG recordings:

- **CEBS** (Combined measurement of ECG, Breathing and Seismocardiograms,
  PhysioNet) — supine SCG with synchronized ECG R-peaks for HR labels.
- Self-collected phone-on-sternum captures logged via the debug bridge,
  labelled against a chest-strap HR monitor.

Window each recording into 6 s segments, resample to 100 Hz, and emit
`.npz` with `envelope` `[N, 1, 600]` (raw) and `bpm` `[N]`. The AO/AC
fiducials for LVET labels can be derived from the synchronized echo or
from the ECG-gated ensemble average.

## Ship into the app

1. Convert to `ZSCardiacSCG.mlpackage` and copy into `ZeroSqueeze/Resources/`.
2. `xcodegen generate` (the `Resources` path auto-includes it) and rebuild.
   Xcode compiles it to `ZSCardiacSCG.mlmodelc`; `CoreMLSCGHeartRateModel`
   picks it up and the router starts preferring it.

## Validation gates

- HR MAE < 3 bpm vs ECG on a held-out supine split.
- Confidence gating at the router threshold (0.5) must improve MAE.
- Spot-check against the classic AO detector on the synthetic AO trains in
  `ZeroSqueezeTests/SCGProcessorTests.swift`.
