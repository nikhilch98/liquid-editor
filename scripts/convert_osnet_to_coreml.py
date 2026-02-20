#!/usr/bin/env python3
"""
Convert OSNet model to CoreML format for person re-identification.

OSNet (Omni-Scale Network) is a lightweight ReID model.
Input: 256x128 RGB image (person crop)
Output: 512-dim feature vector (will be normalized to unit length)
"""

import os
import warnings
warnings.filterwarnings("ignore")

import torch
import torch.nn as nn
import coremltools as ct
from torchreid import models

# Output paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_DIR, "LiquidEditor", "Resources", "Models")
MLPACKAGE_PATH = os.path.join(OUTPUT_DIR, "OSNetReID.mlpackage")

def main():
    print("=" * 60)
    print("OSNet to CoreML Converter")
    print("=" * 60)

    # Step 1: Build OSNet model with pretrained weights
    print("\n[1/4] Loading OSNet model with pretrained weights...")

    # Use osnet_x1_0 - the full-size variant (best accuracy)
    # Other options: osnet_x0_75, osnet_x0_5, osnet_x0_25 (smaller/faster)
    model = models.build_model(
        name='osnet_x1_0',
        num_classes=1000,  # Dummy, we'll remove classifier
        pretrained=True,
        loss='softmax'
    )
    model.eval()

    print(f"   Model loaded: osnet_x1_0")
    print(f"   Feature dimension: {model.feature_dim}")

    # Step 2: Remove classifier head - we only need features
    print("\n[2/4] Removing classifier head...")

    # Create a wrapper that only returns features
    class OSNetFeatureExtractor(nn.Module):
        def __init__(self, backbone):
            super().__init__()
            self.backbone = backbone

        def forward(self, x):
            # Get features before classifier
            features = self.backbone.featuremaps(x)
            # Global average pooling
            features = self.backbone.global_avgpool(features)
            features = features.view(features.size(0), -1)

            # L2 normalize
            features = nn.functional.normalize(features, p=2, dim=1)

            return features

    feature_extractor = OSNetFeatureExtractor(model)
    feature_extractor.eval()

    # Verify output shape
    dummy_input = torch.randn(1, 3, 256, 128)
    with torch.no_grad():
        dummy_output = feature_extractor(dummy_input)
    print(f"   Output shape: {dummy_output.shape}")
    print(f"   Output is normalized: {torch.allclose(dummy_output.norm(dim=1), torch.ones(1), atol=1e-5)}")

    # Step 3: Trace the model
    print("\n[3/4] Tracing model for export...")

    traced_model = torch.jit.trace(feature_extractor, dummy_input)

    # Step 4: Convert to CoreML
    print("\n[4/4] Converting to CoreML...")

    # Define input as an image
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, 256, 128),
                scale=1/255.0,  # Normalize to [0, 1]
                bias=[-0.485/0.229, -0.456/0.224, -0.406/0.225],  # ImageNet normalization
                color_layout=ct.colorlayout.RGB
            )
        ],
        outputs=[
            ct.TensorType(name="embedding")
        ],
        minimum_deployment_target=ct.target.iOS15,
        convert_to="mlprogram"  # Use ML Program format for better performance
    )

    # Add metadata
    mlmodel.author = "Liquid Editor"
    mlmodel.short_description = "OSNet person re-identification model for tracking"
    mlmodel.version = "1.0"

    # Add input/output descriptions
    spec = mlmodel.get_spec()

    # Save the model
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    mlmodel.save(MLPACKAGE_PATH)

    print(f"\n{'=' * 60}")
    print("SUCCESS!")
    print(f"{'=' * 60}")
    print(f"\nModel saved to: {MLPACKAGE_PATH}")
    print(f"\nModel details:")
    print(f"  - Input: 256x128 RGB image")
    print(f"  - Output: 512-dim normalized feature vector")
    print(f"  - Format: ML Program (.mlpackage)")
    print(f"\nNext steps:")
    print(f"  1. Open the .mlpackage in Xcode to compile it")
    print(f"  2. Add OSNetReID.mlmodelc to your Xcode project")
    print(f"  3. Or drag the .mlpackage directly into Xcode project")

if __name__ == "__main__":
    main()
