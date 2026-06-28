"""Train SCGCNN on preprocessed seismocardiography envelopes.

Data: directory of .npz files, each with:
  envelope [N, 1, 600] float32  — raw (unnormalized) accel-magnitude traces
  bpm      [N]         float32  — ground-truth HR
  subject  [N]         int/str  — optional subject ids; when present the
                                  train/val split is by subject, so windows
                                  from one recording never leak across splits

Usage:
  python train_scg.py --data ./scg_data --epochs 40 --out checkpoints/
"""

import argparse
import glob
import os

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset

from scg_cnn import SCGCNN

CONFIDENCE_ERR_BPM = 4.0  # confidence target: |err| < 4 bpm


def standardize(env: np.ndarray) -> np.ndarray:
    """Per-trace zero-mean/unit-variance — must mirror the app's
    CoreMLSCGHeartRateModel.envelopeTensor preprocessing exactly."""
    mean = env.mean(axis=-1, keepdims=True)
    std = np.maximum(env.std(axis=-1, keepdims=True), 1e-6)
    return (env - mean) / std


def load(data_dir: str):
    envs, bpms, subjects = [], [], []
    for fi, path in enumerate(sorted(glob.glob(os.path.join(data_dir, "*.npz")))):
        z = np.load(path)
        envs.append(standardize(z["envelope"].astype(np.float32)))
        bpms.append(z["bpm"].astype(np.float32))
        n = len(z["bpm"])
        subjects.append(z["subject"] if "subject" in z else np.full(n, fi))
    if not envs:
        raise SystemExit(f"no .npz files in {data_dir}")
    return np.concatenate(envs), np.concatenate(bpms), np.concatenate(subjects)


def subject_split(subjects: np.ndarray, val_fraction: float, seed: int = 7):
    """Hold out whole subjects for validation — window-level splits leak
    because adjacent windows are near-duplicates."""
    rng = np.random.default_rng(seed)
    unique = rng.permutation(np.unique(subjects))
    n_val = max(1, int(len(unique) * val_fraction))
    val_subjects = set(unique[:n_val].tolist())
    val_mask = np.isin(subjects, list(val_subjects))
    return np.where(~val_mask)[0], np.where(val_mask)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", default="checkpoints")
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--batch", type=int, default=128)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--val-fraction", type=float, default=0.15)
    args = ap.parse_args()

    envs, bpms, subjects = load(args.data)
    train_idx, val_idx = subject_split(subjects, args.val_fraction)
    print(f"{len(train_idx)} train / {len(val_idx)} val windows "
          f"({len(np.unique(subjects[val_idx]))} held-out subjects)")

    train_ds = TensorDataset(torch.from_numpy(envs[train_idx]), torch.from_numpy(bpms[train_idx]))
    val_ds = TensorDataset(torch.from_numpy(envs[val_idx]), torch.from_numpy(bpms[val_idx]))
    train_dl = DataLoader(train_ds, batch_size=args.batch, shuffle=True)
    val_dl = DataLoader(val_ds, batch_size=args.batch)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = SCGCNN().to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr)
    os.makedirs(args.out, exist_ok=True)
    best_mae = float("inf")

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
        abs_err = []
        with torch.no_grad():
            for x, y in val_dl:
                bpm, _ = model(x.to(device))
                y = y.to(device).unsqueeze(1)
                abs_err.append((bpm - y).abs().cpu().numpy())
        mae = float(np.concatenate(abs_err).mean())
        print(f"epoch {epoch + 1}/{args.epochs}  val MAE {mae:.2f} bpm")
        if mae < best_mae:
            best_mae = mae
            torch.save(model.state_dict(), os.path.join(args.out, "scg_best.pt"))

    print(f"best val MAE {best_mae:.2f} bpm -> {args.out}/scg_best.pt")


if __name__ == "__main__":
    main()
