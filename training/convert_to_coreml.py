"""Convert a trained TraceCNN checkpoint to ZSHR.mlpackage.

Enforces the app's model contract (see CoreMLHeartRateModel.swift):
  input  "trace"      Float32 [1, 3, 240]
  output "bpm"        Float32 [1]
  output "confidence" Float32 [1]

Usage:
  python convert_to_coreml.py checkpoints/best.pt ZSHR.mlpackage
"""

import sys

import coremltools as ct
import torch

from trace_cnn import CHANNELS, TRACE_LEN, TraceCNN


class Wrapped(torch.nn.Module):
    """Flatten the two heads to the [1]-shaped outputs the app reads."""

    def __init__(self, model: TraceCNN):
        super().__init__()
        self.model = model

    def forward(self, trace):
        bpm, confidence = self.model(trace)
        return bpm.reshape(1), confidence.reshape(1)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    checkpoint, out_path = sys.argv[1], sys.argv[2]

    model = TraceCNN()
    model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    model.eval()
    wrapped = Wrapped(model).eval()

    example = torch.zeros(1, CHANNELS, TRACE_LEN)
    traced = torch.jit.trace(wrapped, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="trace", shape=(1, CHANNELS, TRACE_LEN), dtype=float)],
        outputs=[ct.TensorType(name="bpm"), ct.TensorType(name="confidence")],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,  # CPU + GPU + Neural Engine
    )
    mlmodel.short_description = (
        "ZeroSqueeze heart-rate trace model (temporal-shift 1D CNN). "
        "8 s, 3-channel, 30 Hz standardized mean-ROI trace -> bpm + confidence."
    )
    mlmodel.save(out_path)
    print(f"saved {out_path}")


if __name__ == "__main__":
    main()
