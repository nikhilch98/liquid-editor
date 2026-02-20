# Tracking Tester

A local development tool for testing the Box Tracking algorithm without deploying to iOS.

## Architecture

```
┌─────────────────────┐     HTTP     ┌─────────────────────┐
│   Chrome Web Page   │ ◄──────────► │  Swift Local Server │
│  - Video Player     │   Frames &   │  - Vision Framework │
│  - Canvas Overlay   │   Results    │  - Same Algorithm   │
│  - Controls         │              │  - Port 8080        │
└─────────────────────┘              └─────────────────────┘
```

## Quick Start

### 1. Start the Server

```bash
cd tools/tracking-tester
swift run
```

You should see:
```
Starting Tracking Tester Server on http://localhost:8080
Open the web page at: file:///.../web/index.html
Press Ctrl+C to stop
```

### 2. Open the Web UI

Open `web/index.html` in Chrome:

```bash
open web/index.html
```

Or drag and drop the file into Chrome.

### 3. Analyze a Video

1. Click **"Load Local File"** to select a video for preview
2. Enter the **full path** to the video in the text field (e.g., `/Users/you/Videos/dance.mp4`)
3. Set **Stride** (1 = every frame, 2 = every other frame, etc.)
4. Click **Analyze**

The server will process the video using the exact same Vision framework code as the iOS app.

## Features

- **Same Algorithm**: Uses `VNDetectHumanBodyPoseRequest` and the same tracking logic as `BoundingBoxTracker.swift`
- **Visual Debugging**: See bounding boxes overlaid on the video in real-time
- **Frame-by-Frame**: Step through frames using arrow keys or buttons
- **Person Tracking**: Color-coded boxes show person IDs across frames
- **Statistics**: View total detections, unique persons, and confidence levels

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Space | Play/Pause |
| ← | Previous frame |
| → | Next frame |

## API Endpoints

### `GET /health`
Health check endpoint.

### `POST /analyze`
Analyze a video file.

Request body:
```json
{
  "videoPath": "/path/to/video.mp4",
  "stride": 1
}
```

Response:
```json
{
  "totalFrames": 300,
  "duration": 10.0,
  "fps": 30.0,
  "frames": [
    {
      "frameNumber": 0,
      "timestampMs": 0,
      "people": [
        {
          "personIndex": 0,
          "confidence": 0.95,
          "boundingBox": {
            "x": 0.5,
            "y": 0.5,
            "width": 0.3,
            "height": 0.6
          }
        }
      ]
    }
  ]
}
```

## Troubleshooting

### Server won't start
- Make sure port 8080 is not in use
- Run with `swift run` from the `tracking-tester` directory

### Video won't load in browser
- Use the "Load Local File" button to load videos for preview
- The browser cannot access arbitrary file paths for security reasons
- The video path in the text field is sent to the server, which can access local files

### Tracking results don't match iOS
- Ensure you're using the same video file
- Check the stride value (1 processes every frame)
- The algorithm is identical, but frame extraction timing may differ slightly

## Development

To modify the tracking algorithm, edit `Sources/main.swift`. The `BoxTracker` class mirrors the iOS implementation.

Rebuild with:
```bash
swift build
```

Run with:
```bash
swift run
```
