"""Convert a trained SCGCNN checkpoint to ZSCardiacSCG.mlpackage.

Enforces the app's model contract (see SCGHeartRateModel.swift):
  input  "envelope"   Float32 [1, 1, 600]
  output "bpm"        Float32 [1]
  output "confidence" Float32 [1]

Usage:
  python convert_scg_coreml.py checkpoints/scg_best.pt ZSCardiacSCG.mlpackage
"""

import sys

import coremltools as ct
import torch

from scg_cnn import CHANNELS, TRACE_LEN, SCGCNN


class Wrapped(torch.nn.Module):
    """Flatten the two heads to the [1]-shaped outputs the app reads."""

    def __init__(self, model: SCGCNN):
        super().__init__()
        self.model = model

    def forward(self, envelope):
        bpm, confidence = self.model(envelope)
        return bpm.reshape(1), confidence.reshape(1)


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    checkpoint, out_path = sys.argv[1], sys.argv[2]

    model = SCGCNN()
    model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    model.eval()
    wrapped = Wrapped(model).eval()

    example = torch.zeros(1, CHANNELS, TRACE_LEN)
    traced = torch.jit.trace(wrapped, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="envelope", shape=(1, CHANNELS, TRACE_LEN), dtype=float)],
        outputs=[ct.TensorType(name="bpm"), ct.TensorType(name="confidence")],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,  # CPU + GPU + Neural Engine
    )
    mlmodel.short_description = (
        "ZeroSqueeze SCG heart-rate model (1D CNN). 6 s, single-channel, "
        "100 Hz standardized accelerometer-magnitude trace -> bpm + confidence."
    )
    mlmodel.save(out_path)
    print(f"saved {out_path}")


if __name__ == "__main__":
    main()
