"""Build SCG training data from the PhysioNet CEBS database (real chest
seismocardiography + synchronized ECG).

CEBS: "Combined measurement of ECG, Breathing and Seismocardiograms"
(physionet.org/content/cebsdb). Each record has 4 channels at 5000 Hz:
ECG lead I, ECG lead II, RESP, and SCG (a sternum accelerometer). We use the
SCG channel as the model input and ECG R-peaks as the ground-truth HR label.

Pipeline per record:
  1. Stream the record via wfdb (no manual download).
  2. Detect R-peaks on ECG lead II (wfdb XQRS) → ground-truth instantaneous HR.
  3. Decimate the SCG channel 5000 Hz → 100 Hz (matches the app's input rate).
  4. Slide a 6 s / 600-sample window; label each window with the median
     RR-derived HR over that window. Drop windows with too few/implausible
     beats.
  5. Emit one .npz per record: envelope [N,1,600] (raw), bpm [N], subject [N].

Output matches train_scg.py's contract. Subjects are kept per-record so the
subject-held-out split in train_scg.py is honoured.

Usage:
  python prep_cebs.py --out ./cebs_data --records 16
"""

import argparse
import os

import numpy as np
import wfdb
from wfdb import processing
from scipy.signal import decimate

PN_DIR = "cebsdb/1.0.0"
SRC_FS = 5000
DST_FS = 100
WIN_S = 6
WIN_N = WIN_S * DST_FS          # 600
STEP_S = 3                      # 50% overlap


def hr_series(ecg: np.ndarray, fs: int):
    """R-peak sample indices on ECG lead II via wfdb's XQRS."""
    try:
        xqrs = processing.XQRS(sig=ecg.astype(np.float64), fs=fs)
        xqrs.detect(verbose=False)
        return np.asarray(xqrs.qrs_inds, dtype=np.int64)
    except Exception:
        return np.array([], dtype=np.int64)


def window_hr(rpeaks_t: np.ndarray, t0: float, t1: float):
    """Median-RR heart rate (bpm) from R-peak times inside [t0, t1]."""
    inside = rpeaks_t[(rpeaks_t >= t0) & (rpeaks_t <= t1)]
    if len(inside) < 4:
        return None
    rr = np.diff(inside)
    rr = rr[(rr > 0.3) & (rr < 1.7)]      # 35–200 bpm physiological gate
    if len(rr) < 3:
        return None
    return 60.0 / float(np.median(rr))


def process_record(name: str, sid: int):
    rec = wfdb.rdrecord(name, pn_dir=PN_DIR)
    names = [s.upper() for s in rec.sig_name]
    scg_i = names.index("SCG")
    ecg_i = names.index("II") if "II" in names else names.index("I")
    fs = int(rec.fs)

    scg = rec.p_signal[:, scg_i].astype(np.float64)
    ecg = rec.p_signal[:, ecg_i].astype(np.float64)

    # R-peak detection on the raw 5 kHz ECG is very slow; decimate to 250 Hz
    # first (XQRS's native range) and scale the peak times back to seconds.
    ecg_fs = 250
    ecg_ds = decimate(ecg, 10, ftype="fir", zero_phase=True)
    ecg_ds = decimate(ecg_ds, 2, ftype="fir", zero_phase=True)   # 5000 -> 250
    rpeaks = hr_series(ecg_ds, ecg_fs)
    if len(rpeaks) < 10:
        return None
    rpeaks_t = rpeaks / ecg_fs

    # 5000 -> 100 Hz in two stable decimation stages (50 = 10 * 5).
    scg_ds = decimate(scg, 10, ftype="fir", zero_phase=True)
    scg_ds = decimate(scg_ds, 5, ftype="fir", zero_phase=True)
    ds_fs = fs / 50.0

    envs, bpms = [], []
    n = len(scg_ds)
    step = int(STEP_S * ds_fs)
    win = int(WIN_S * ds_fs)
    for start in range(0, n - win, step):
        seg = scg_ds[start:start + win]
        t0, t1 = start / ds_fs, (start + win) / ds_fs
        hr = window_hr(rpeaks_t, t0, t1)
        if hr is None:
            continue
        # Resample the segment to exactly WIN_N if decimation rate drifted.
        if len(seg) != WIN_N:
            idx = np.linspace(0, len(seg) - 1, WIN_N)
            seg = np.interp(idx, np.arange(len(seg)), seg)
        envs.append(seg.astype(np.float32))
        bpms.append(np.float32(hr))

    if not envs:
        return None
    env = np.stack(envs)[:, None, :]               # [N, 1, 600]
    bpm = np.asarray(bpms, dtype=np.float32)
    subject = np.full(len(bpm), sid, dtype=int)
    return env, bpm, subject


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="cebs_data")
    ap.add_argument("--records", type=int, default=16, help="number of basal records b001..")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    total_win = 0
    for sid in range(1, args.records + 1):
        name = f"b{sid:03d}"
        try:
            res = process_record(name, sid)
        except Exception as e:
            print(f"{name}: skip ({e})")
            continue
        if res is None:
            print(f"{name}: no usable windows")
            continue
        env, bpm, subject = res
        np.savez(os.path.join(args.out, f"{name}.npz"), envelope=env, bpm=bpm, subject=subject)
        total_win += len(bpm)
        print(f"{name}: {len(bpm):4d} windows  HR {bpm.min():.0f}-{bpm.max():.0f} bpm")
    print(f"total {total_win} windows -> {args.out}/")


if __name__ == "__main__":
    main()
