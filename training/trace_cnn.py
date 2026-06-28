"""Trace-based HR model: 1D temporal-shift CNN over an 8 s, 3-channel,
30 Hz mean-ROI trace. Outputs bpm and a self-assessed confidence.

Input  [B, 3, 240]  (per-channel standardized)
Output bpm [B, 1], confidence [B, 1] in [0, 1]
"""

import torch
import torch.nn as nn

TRACE_LEN = 240
CHANNELS = 3


class TemporalShift(nn.Module):
    """Zero-FLOP temporal mixing (TSM): shift 1/8 of channels one step
    back in time, 1/8 one step forward, rest untouched.

    `fold` is derived from a *static* channel count at construction. Computing
    it from `x.size(1)` at runtime forced an `aten::Int` cast over a non-scalar
    that Core ML conversion can't const-fold; the value is identical either way
    (channel counts are fixed by the architecture). This module has no learnable
    parameters, so existing checkpoints load unchanged and outputs are bit-identical."""

    def __init__(self, channels: int, fold_div: int = 8):
        super().__init__()
        self.fold = max(1, channels // fold_div)

    def forward(self, x: torch.Tensor) -> torch.Tensor:  # [B, C, T]
        fold = self.fold
        # cat of statically-sliced, ZERO-padded shifts — bit-equivalent to the
        # original zero-init slice-assignment (the boundary column was 0 there
        # too), but without the in-place writes Core ML's converter mishandles.
        pad = torch.zeros_like(x[:, :fold, :1])
        left = torch.cat([x[:, :fold, 1:], pad], dim=2)            # shift left, last col 0
        right = torch.cat([pad, x[:, fold:2 * fold, :-1]], dim=2)  # shift right, first col 0
        rest = x[:, 2 * fold:]
        return torch.cat([left, right, rest], dim=1)


def conv_block(cin: int, cout: int, stride: int = 2) -> nn.Sequential:
    return nn.Sequential(
        TemporalShift(cin),
        nn.Conv1d(cin, cout, kernel_size=7, stride=stride, padding=3),
        nn.BatchNorm1d(cout),
        nn.SiLU(),
    )


class TraceCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.backbone = nn.Sequential(
            conv_block(CHANNELS, 16),   # 240 -> 120
            conv_block(16, 32),         # 120 -> 60
            conv_block(32, 64),         # 60  -> 30
            conv_block(64, 64),         # 30  -> 15
            nn.AdaptiveAvgPool1d(1),
        )
        self.bpm_head = nn.Sequential(
            nn.Flatten(), nn.Linear(64, 32), nn.SiLU(), nn.Linear(32, 1)
        )
        self.conf_head = nn.Sequential(
            nn.Flatten(), nn.Linear(64, 32), nn.SiLU(), nn.Linear(32, 1), nn.Sigmoid()
        )

    def forward(self, trace: torch.Tensor):
        feat = self.backbone(trace)
        # Predict bpm as 40 + 180 * sigmoid -> bounded [40, 220], keeps
        # early training stable and the Core ML output physiological.
        bpm = 40.0 + 180.0 * torch.sigmoid(self.bpm_head(feat))
        confidence = self.conf_head(feat)
        return bpm, confidence
