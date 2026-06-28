# ZeroSqueeze — iOS

On-device cardiac modelling that runs entirely on an iPhone — no
wearable, no cuff, no needle. Two sensing modalities, fused into a
heart-health picture:

- **Chest SCG** — lie back and rest the phone on your breastbone. The
  accelerometer reads the micro-vibrations of each heartbeat
  (seismocardiography) for heart rate, HRV, respiration, **left-ventricular
  ejection time (LVET)**, contractility, and a modelled **blood-pressure
  index**.
- **Finger PPG** — cover the rear camera and torch with a fingertip for
  heart rate, perfusion and a hemoglobin estimate.

- **Heart Check (fused, the capstone)** — press the phone to your chest and
  rest a fingertip on the rear camera at the *same time*. The chest SCG and
  finger PPG together give **pulse transit time** (SCG AO → finger pulse),
  which yields a **cuffless blood-pressure** index, a **heart-health score**
  and an estimated **heart age**. Neither sensor alone gives PTT — the fusion
  is the point.

There is **no face/rPPG** path — all sensing is contact-based (chest +
fingertip).

> **Not a medical device.** ZeroSqueeze produces wellness estimates.
> Confirm any concerning result with a clinician and proper instruments.

## Generate the Xcode project

```bash
brew install xcodegen
cd ~/Downloads/ZeroSqueezeiOS
xcodegen generate
open ZeroSqueeze.xcodeproj
```

Set `DEVELOPMENT_TEAM` in `project.yml` (or via Xcode signing UI) before
running on device. Bundle identifier defaults to `com.zerosqueeze.ios`.
SCG capture needs a physical device — the simulator has no accelerometer.

## How it works

### Chest SCG (the primary modality)

1. **Capture** — `SCGService` streams CoreMotion device-motion at 100 Hz.
   `userAcceleration` already has gravity removed by the sensor-fusion
   filter, so what's left is body + cardiac wall motion. A contact gate
   waits for the phone to be still on a beating chest before arming.
2. **Detect** — `SCGProcessor` detrends the vector-magnitude trace, builds
   a Pan-Tompkins-style energy envelope, and runs an adaptive-threshold
   peak detector to find the **AO** (aortic-valve opening) complex of each
   beat → inter-beat intervals → heart rate + HRV (SDNN).
3. **Model** — per beat it searches the systolic window for the **AC**
   (aortic-valve closing) lobe to recover **LVET = AO→AC**, a systolic time
   interval. `BloodPressureEstimator` combines LVET with heart rate via
   Weissler's rate-correction to produce a systolic/diastolic index
   (computational-physiology model, not a cuff). AO amplitude is reported
   as a relative contractility proxy.
4. **Learn (optional)** — `SCGHeartRateModel` is a pluggable backend stack:
   the classic AO detector always runs; a learned 1-D CNN
   (`CoreMLSCGHeartRateModel`, loads `ZSCardiacSCG.mlmodelc` when bundled)
   is preferred when confident. `SCGHeartRateModelRouter` gates on
   confidence and falls back to classic. See `training/`.

### Finger PPG (secondary)

`CameraPPGService` locks exposure/focus/white-balance, drives the torch at
~60%, and averages a centred ROI per frame at 30 fps. `PPGProcessor` runs
the rolling peak detector; `HemoglobinEstimator` blends a demographic
baseline, perfusion index, red/green AC-ratio, a Monk skin-tone correction
and a personal calibration into an Hb point estimate with a confidence
band. The learned `CoreMLHeartRateModel` (`ZSHR.mlmodelc`) upgrades HR when
bundled.

### Fused Heart Check (chest SCG + finger PPG together)

`HeartCheckViewModel` runs `SCGService` and `CameraPPGService` concurrently and
re-stamps both streams on one monotonic clock (`CACurrentMediaTime`).
`PulseTransitTime` detects SCG AO peaks and finger-PPG systolic peaks, pairs
each AO with the next finger pulse, and takes the robust (median) transit time.
`HeartHealthModel` maps PTT → cuffless systolic/diastolic (BP falls as PTT
lengthens), then folds HR, HRV, BP and LVET into a 0–100 cardiovascular score
and a heart-age estimate vs the user's chronological age. All in
`Data/Fusion/`.

## Computational biology, briefly

- **Seismocardiography** turns the phone into a contact ballistography
  sensor: the heart's mechanical contraction couples into the chest wall,
  and the AO/AC fiducial points are the same ones clinical SCG/echo use.
- **Systolic time intervals** (LVET, and PEP-adjacent timing) are
  established surrogates for contractility and loading conditions. The BP
  index is anchored to a normotensive reference and reported as a band —
  it is an *index*, deliberately not presented as a measurement.
- **Confidence gating** runs end to end: low-quality beats are excluded
  from HR/HRV/LVET, and the BP confidence scales with signal quality and
  beat count.

## Layout

| Layer | Files |
|-------|-------|
| Domain | `Domain/Model/*.swift` — `UserProfile`, `HbMeasurement`, `SCGMeasurement`, `AnemiaStatus`, … |
| SCG | `Data/SCG/{SCGSample,SCGService,SCGProcessor,SCGHeartRateModel}.swift` |
| Fusion | `Data/Fusion/BloodPressureEstimator.swift` |
| Camera/PPG | `Data/Camera/CameraPPGService.swift`, `Data/PPG/{PPGSample,PPGProcessor,HemoglobinEstimator}.swift` |
| HR model | `Data/HR/{HeartRateModel,CoreMLHeartRateModel}.swift` |
| Storage | `Data/Storage/{ProfileStore,MeasurementStore,SCGMeasurementStore,CheckInStore}.swift` |
| UI | `Presentation/{Onboarding,Today,Scan,Capture,Result,History,Settings}/*` |
| Theme | `Presentation/Theme/{ZSPalette,ZSTheme}.swift` |
| App | `ZeroSqueezeApp.swift` |

## Tests

```bash
xcodebuild test -project ZeroSqueeze.xcodeproj -scheme ZeroSqueeze \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Suites cover the SCG beat detector on synthetic AO trains, the
systolic-time-interval BP model (monotonicity, clamping, buckets), the HR
model router fallback, PPG peak detection, hemoglobin estimation,
readiness, resting-HR aggregation, and store persistence/decoding.

## Roadmap

- ✅ **Done** — `ZSCardiacSCG.mlpackage` is trained on real chest SCG
  (PhysioNet CEBS, 14 subjects / 1363 windows, 1.96 bpm subject-held-out
  MAE) and bundled. Pipeline in `training/` (`prep_cebs.py` → `train_scg.py`
  → `convert_scg_coreml.py`).
- Expand the SCG training set beyond CEBS (more subjects, free-living, motion).
- Simultaneous PPG+SCG capture to recover true **pulse transit time** for a
  calibrated (vs indexed) blood-pressure estimate.
- Per-user BP calibration against a cuff, mirroring the Hb calibration flow.
