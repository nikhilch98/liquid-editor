#!/usr/bin/env python3
"""
Convert YOLOv8n-pose to CoreML format for iOS deployment.

Requirements:
    pip install ultralytics coremltools

Usage:
    python convert_yolo_to_coreml.py

Output:
    LiquidEditor/Resources/Models/yolov8n-pose.mlpackage
"""

import os
import sys

def main():
    try:
        from ultralytics import YOLO
    except ImportError:
        print("Error: ultralytics not installed. Run: pip install ultralytics")
        sys.exit(1)

    # Get script directory and project root
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    output_dir = os.path.join(project_root, "LiquidEditor", "Resources", "Models")

    print("=" * 60)
    print("YOLOv8n-Pose to CoreML Converter")
    print("=" * 60)

    # Load YOLOv8n-pose (will download if not cached)
    print("\n[1/3] Loading YOLOv8n-pose model...")
    model = YOLO("yolov8n-pose.pt")

    # Export to CoreML
    print("\n[2/3] Converting to CoreML format...")
    print("      - Input size: 640x640")
    print("      - Compute units: ALL (Neural Engine + GPU + CPU)")
    print("      - Half precision: Yes (FP16)")

    model.export(
        format="coreml",
        imgsz=640,
        half=True,  # FP16 for smaller size and faster inference
        nms=False,  # We do NMS in Swift for more control
    )

    # Move to project
    print("\n[3/3] Moving to project...")

    # The export creates yolov8n-pose.mlpackage in current directory
    source = "yolov8n-pose.mlpackage"
    dest = os.path.join(output_dir, "yolov8n-pose.mlpackage")

    if os.path.exists(source):
        import shutil
        if os.path.exists(dest):
            shutil.rmtree(dest)
        os.makedirs(output_dir, exist_ok=True)
        shutil.move(source, dest)
        print(f"      Model saved to: {dest}")
    else:
        print(f"      Warning: Expected {source} not found")
        print(f"      Check current directory for .mlpackage file")

    print("\n" + "=" * 60)
    print("Conversion complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Open LiquidEditor.xcodeproj in Xcode")
    print("2. Add yolov8n-pose.mlpackage to the LiquidEditor target")
    print("3. Ensure 'Copy Bundle Resources' includes the model")
    print("4. Build and run!")
    print()

    # Print model info
    print("Model specifications:")
    print("  - Input:  [1, 3, 640, 640] RGB normalized [0,1]")
    print("  - Output: [1, 56, 8400] detections")
    print("  - Size:   ~13MB (FP16)")
    print("  - Speed:  ~15-20ms on A18 Pro Neural Engine")
    print()

if __name__ == "__main__":
    main()
