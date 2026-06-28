"""Train TraceCNN on preprocessed rPPG traces.

Data: directory of .npz files, each with:
  trace   [N, 3, 240] float32  — raw (unnormalized) mean-ROI traces
  bpm     [N]         float32  — ground-truth HR
  tone    [N]         int      — optional Monk tone (1-10) for equity sampling
  subject [N]         int/str  — optional subject ids; when present the
                                 train/val split is by subject, so windows
                                 from one person never leak across splits

Usage:
  python train.py --data ./data --epochs 50 --out checkpoints/
"""

import argparse
import glob
import os

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset, WeightedRandomSampler

from trace_cnn import TraceCNN

CONFIDENCE_ERR_BPM = 5.0  # confidence target: |err| < 5 bpm


def standardize(trace: np.ndarray) -> np.ndarray:
    """Per-channel zero-mean/unit-variance — must mirror the app's
    CoreMLHeartRateModel.traceTensor preprocessing exactly."""
    mean = trace.mean(axis=-1, keepdims=True)
    std = np.maximum(trace.std(axis=-1, keepdims=True), 1e-6)
    return (trace - mean) / std


def load(data_dir: str):
    traces, bpms, tones, subjects = [], [], [], []
    for fi, path in enumerate(sorted(glob.glob(os.path.join(data_dir, "*.npz")))):
        z = np.load(path)
        traces.append(standardize(z["trace"].astype(np.float32)))
        bpms.append(z["bpm"].astype(np.float32))
        n = len(z["bpm"])
        tones.append(z["tone"] if "tone" in z else np.zeros(n, dtype=int))
        # Without explicit ids, treat each file as one subject — datasets
        # are usually exported one file per participant.
        subjects.append(z["subject"] if "subject" in z else np.full(n, fi))
    if not traces:
        raise SystemExit(f"no .npz files in {data_dir}")
    return (
        np.concatenate(traces),
        np.concatenate(bpms),
        np.concatenate(tones),
        np.concatenate(subjects),
    )


def subject_split(subjects: np.ndarray, val_fraction: float, seed: int = 7):
    """Hold out whole subjects for validation. Window-level random splits
    leak — adjacent windows from the same person are near-duplicates, so
    val MAPE would flatter the model."""
    rng = np.random.default_rng(seed)
    unique = rng.permutation(np.unique(subjects))
    n_val_subjects = max(1, int(len(unique) * val_fraction))
    val_subjects = set(unique[:n_val_subjects].tolist())
    val_mask = np.isin(subjects, list(val_subjects))
    return np.where(~val_mask)[0], np.where(val_mask)[0]


def equity_sampler(tones: np.ndarray, min_dark_fraction: float):
    """Oversample Monk 7-10 so each batch carries at least the target
    fraction of dark tones (PHRM used >= 0.33). No-op without labels."""
    dark = tones >= 7
    if not dark.any() or dark.mean() >= min_dark_fraction:
        return None
    w = np.ones(len(tones))
    w[dark] = (min_dark_fraction / max(dark.mean(), 1e-6)) * (1 - dark.mean()) / (1 - min_dark_fraction)
    return WeightedRandomSampler(torch.from_numpy(w), num_samples=len(tones), replacement=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", default="checkpoints")
    ap.add_argument("--epochs", type=int, default=50)
    ap.add_argument("--batch", type=int, default=128)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--val-fraction", type=float, default=0.15)
    ap.add_argument("--min-dark-fraction", type=float, default=0.33)
    args = ap.parse_args()

    traces, bpms, tones, subjects = load(args.data)
    train_idx, val_idx = subject_split(subjects, args.val_fraction)
    print(f"{len(train_idx)} train / {len(val_idx)} val windows "
          f"({len(np.unique(subjects[val_idx]))} held-out subjects)")

    train_ds = TensorDataset(
        torch.from_numpy(traces[train_idx]), torch.from_numpy(bpms[train_idx])
    )
    val_ds = TensorDataset(
        torch.from_numpy(traces[val_idx]), torch.from_numpy(bpms[val_idx])
    )
    sampler = equity_sampler(tones[train_idx], args.min_dark_fraction)
    train_dl = DataLoader(
        train_ds, batch_size=args.batch,
        sampler=sampler, shuffle=sampler is None,
    )
    val_dl = DataLoader(val_ds, batch_size=args.batch)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = TraceCNN().to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr)
    os.makedirs(args.out, exist_ok=True)
    best_mape = float("inf")

    for epoch in range(args.epochs):
        model.train()
        for x, y in train_dl:
            x, y = x.to(device), y.to(device).unsqueeze(1)
            bpm, conf = model(x)
            err = (bpm - y).abs()
            conf_target = (err.detach() < CONFIDENCE_ERR_BPM).float()
            loss = F.l1_loss(bpm, y) + 0.2 * F.binary_cross_entropy(conf, conf_target)
            opt.zero_grad()
            loss.backward()
            opt.step()

        model.eval()
        ape = []
        with torch.no_grad():
            for x, y in val_dl:
                bpm, _ = model(x.to(device))
                y = y.to(device).unsqueeze(1)
                ape.append(((bpm - y).abs() / y).cpu().numpy())
        mape = float(np.concatenate(ape).mean() * 100)
        print(f"epoch {epoch + 1}/{args.epochs}  val MAPE {mape:.2f}%")
        if mape < best_mape:
            best_mape = mape
            torch.save(model.state_dict(), os.path.join(args.out, "best.pt"))

    print(f"best val MAPE {best_mape:.2f}% -> {args.out}/best.pt")


if __name__ == "__main__":
    main()
