"""SCG HR model: 1D CNN over a 6 s, single-channel, 100 Hz accelerometer
magnitude trace. Outputs bpm and a self-assessed confidence.

Input  [B, 1, 600]  (standardized: zero mean, unit variance)
Output bpm [B, 1], confidence [B, 1] in [0, 1]

Mirrors trace_cnn.py (PPG) but for the seismocardiography contract in
`SCGHeartRateModel.swift`: one channel, 600-sample window. Strided conv
stack with SiLU; bpm bounded to a physiological range via sigmoid so the
Core ML output never goes out of band.
"""

import torch
import torch.nn as nn

TRACE_LEN = 600
CHANNELS = 1


def conv_block(cin: int, cout: int, stride: int = 2) -> nn.Sequential:
    return nn.Sequential(
        nn.Conv1d(cin, cout, kernel_size=7, stride=stride, padding=3),
        nn.BatchNorm1d(cout),
        nn.SiLU(),
    )


class SCGCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.backbone = nn.Sequential(
            conv_block(CHANNELS, 16),   # 600 -> 300
            conv_block(16, 32),         # 300 -> 150
            conv_block(32, 64),         # 150 -> 75
            conv_block(64, 64),         # 75  -> 38
            conv_block(64, 64),         # 38  -> 19
            nn.AdaptiveAvgPool1d(1),
        )
        self.bpm_head = nn.Sequential(
            nn.Flatten(), nn.Linear(64, 32), nn.SiLU(), nn.Linear(32, 1)
        )
        self.conf_head = nn.Sequential(
            nn.Flatten(), nn.Linear(64, 32), nn.SiLU(), nn.Linear(32, 1), nn.Sigmoid()
        )

    def forward(self, envelope: torch.Tensor):
        feat = self.backbone(envelope)
        # bpm bounded to [40, 200] — keeps early training stable and the
        # exported Core ML output physiological.
        bpm = 40.0 + 160.0 * torch.sigmoid(self.bpm_head(feat))
        confidence = self.conf_head(feat)
        return bpm, confidence
