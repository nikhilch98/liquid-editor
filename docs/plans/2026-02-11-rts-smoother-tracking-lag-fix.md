# RTS Smoother: Eliminating Tracking Lag for Fast Movements

**Date:** 2026-02-11
**Status:** Design (Reviewed — 3 critical issues fixed)
**Priority:** Critical (tracking unusable for fast dance movements)

---

## 1. Problem Statement

Skeleton tracking and bounding boxes lag 5+ frames (~170ms at 30fps) behind the actual person position during fast movements (dance spins, jumps, rapid gestures). This makes tracking unusable for professional dance video editing.

### Symptom
The bounding boxes and skeleton overlay visibly trail behind the dancer's actual position. The faster the movement, the worse the lag. At extreme speeds (rapid spins), the lag exceeds 5 frames.

### Root Cause
Three independent layers of **forward-only (causal) smoothing** compound to create severe lag:

| Layer | Location | Mechanism | Lag Contribution |
|-------|----------|-----------|-----------------|
| **Bbox center Kalman** | `TrackingDataStore.applySmoothing()` | Process noise 0.01, measurement noise 0.1 | ~3-4 frames |
| **Per-joint Kalman (x19)** | `TrackingDataStore.applySmoothing()` | Process noise 0.02, measurement noise 0.08 | ~2-3 frames |
| **Bbox size running avg** | `TrackingDataStore.smoothBoundingBoxes()` | Alpha 0.1 forward-only EMA | ~1-2 frames |

All three are **causal filters** — they only use past data. But this is a **batch video editor**, not a live camera feed. We have access to ALL frames (past AND future). The current code never exploits future frames for smoothing.

### Why Existing Mitigations Are Insufficient

The adaptive process noise (1-50x scaling in `KalmanFilter2D.correct()` line 170) helps the filter respond faster to sudden motion, but it **cannot eliminate lag** because:
1. The filter state (velocity) takes multiple frames to ramp up
2. The higher process noise reduces smoothing quality everywhere, not just during fast motion
3. It's still fundamentally forward-only

The existing `applyIntegralSmoothing()` (Gaussian-weighted bidirectional window at line 445) was already **removed from the pipeline** with the comment "it dampens fast movements." Gaussian averaging blurs ALL motion equally. RTS is different — it's the mathematically optimal smoother that preserves real motion while eliminating noise.

---

## 2. Solution: Rauch-Tung-Striebel (RTS) Smoother

### 2.1 Algorithm Overview

The RTS smoother is a **two-pass** optimal smoother for linear state-space models:

**Forward pass** (already exists): Standard Kalman filter runs frame 0 -> N, producing at each frame k:
- `x_k|k` — Filtered state estimate (position + velocity given data up to k)
- `P_k|k` — Filtered covariance (uncertainty given data up to k)

**Backward pass** (new): Runs frame N -> 0, computing at each frame k:
```
// Recompute predicted values from filtered values (no storage needed):
x_{k+1|k} = F * x_k|k
P_{k+1|k} = F * P_k|k * F^T + Q_k

// RTS equations:
G_k       = P_k|k * F^T * inv(P_{k+1|k})             // Smoother gain
x_k|N     = x_k|k + G_k * (x_{k+1|N} - x_{k+1|k})   // Smoothed state
```

Where:
- `F` = state transition matrix `[[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]`
- `Q_k` = process noise matrix (stored per-snapshot to preserve adaptive noise)
- `x_{k+1|N}` = smoothed state from previous backward step (initialized to `x_N|N` at last frame)

### 2.2 Key Design Decision: Recompute Predicted Values in Backward Pass

**Problem identified in review:** Storing predicted values (`x_{k+1|k}`, `P_{k+1|k}`) alongside filtered values creates ambiguous indexing — the predicted state for frame k+1 is computed during frame k's update, but stored in which snapshot? This caused a critical indexing bug in the initial design.

**Solution:** Store ONLY filtered values (`x_k|k`, `P_k|k`) plus the adaptive process noise `q_k` in each snapshot. During the backward pass, recompute the predicted values:
```
x_{k+1|k} = F * x_k|k
P_{k+1|k} = F * P_k|k * F^T + Q(q_k, dt)
```

This eliminates all indexing ambiguity. The forward pass's `dt` and `F` matrix are constant across frames. The only per-frame variation is the adaptive process noise `q_k`, which we store explicitly.

**Benefits:**
- No indexing confusion (each snapshot stores values AT frame k, period)
- First-frame snapshot is captured normally (after correct(), just like every other frame)
- ~40% less memory per snapshot (160 bytes vs 320 bytes — no predicted state/covariance)
- Total memory: ~57 MB instead of ~115 MB for 1-min 60fps video with 5 people

### 2.3 Why RTS Eliminates Lag

During a fast spin, the forward Kalman sees:
- Frame 10: person at position A (velocity = 0)
- Frame 11: person at position A + large_jump (velocity ramps up slowly)
- Frame 12: person at position A + 2*large_jump (velocity still catching up)

The forward filter lags because it takes several frames to update its velocity estimate.

The RTS backward pass sees:
- Frame 12: person WAS at A + 2*large_jump
- Frame 11: person WAS at A + large_jump
- Frame 10: person WAS at A (but backward pass knows motion is coming)

The merge produces the **optimal estimate** at each frame given ALL data. The result is centered on the true position with zero systematic lag.

### 2.4 Why RTS Doesn't Dampen Fast Movements (Unlike Gaussian)

The removed `applyIntegralSmoothing()` used Gaussian-weighted averaging, which treats all motion as noise and averages it away. The RTS smoother is fundamentally different:

1. **Model-based**: It uses the constant-velocity motion model, so it EXPECTS motion and preserves it
2. **Noise-aware**: It only removes the measurement noise component, not the signal
3. **Adaptive**: The forward pass's adaptive process noise (1-50x scaling) is stored per-snapshot and used during backward pass recomputation
4. **Optimal**: It's the minimum-variance estimator for linear Gaussian systems

### 2.5 Memory Budget

**Revised after review** — storing only filtered values + adaptive noise:

Per-Snapshot Storage (160 bytes):
```
filteredState:       4 x Double =  32 bytes   // [x, y, vx, vy]
filteredCovariance:  4x4 x Double = 128 bytes  // P_k|k
adaptiveProcessNoise: 1 x Double =   8 bytes   // q_k (for recomputing Q in backward pass)
```

For a 1-minute 1080p 60fps video with ~5 people (simultaneous storage):

| Component | Count | Per-snapshot | Total |
|-----------|-------|-------------|-------|
| Bbox center | 5 x 3,600 | 160 bytes | 2.7 MB |
| 19 joints/person | 5 x 3,600 x 19 | 160 bytes | 54.7 MB |
| **Total** | | | **~57 MB** |

Stored for the duration of the backward pass, then freed. Well within the 200MB memory budget.

---

## 3. File-by-File Changes

### 3.1 `ios/Runner/Tracking/KalmanFilter.swift`

**New struct** — `KalmanSnapshot`:
```swift
/// Stores forward-pass filtered state for the RTS backward smoother.
/// Only filtered values are stored. Predicted values are recomputed
/// in the backward pass to avoid indexing ambiguity.
struct KalmanSnapshot {
    let filteredState: [Double]        // x_k|k  (4 elements: x, y, vx, vy)
    let filteredCovariance: [[Double]]  // P_k|k  (4x4)
    let adaptiveProcessNoise: Double   // q_k (adaptive noise at this frame)
}
```

**Modified method** — `update(measurement:) -> CGPoint`:
- Add an overload: `update(measurement:, collectSnapshot:) -> (CGPoint, KalmanSnapshot?)`
- Capture timing: AFTER `predict()` and `correct()` complete, snapshot captures:
  - `filteredState = self.state` (this is `x_k|k` — the corrected state)
  - `filteredCovariance = self.P` (this is `P_k|k` — the corrected covariance)
  - `adaptiveProcessNoise = self.adaptiveProcessNoise` (the noise level used during this frame's predict)
- First frame (initialization): returns a valid snapshot — state is initialized directly, P is the initial high-uncertainty covariance, noise is the base level. This is correct because the first frame's "filtered" estimate IS the initialization.
- The existing `update(measurement:) -> CGPoint` calls the new overload with `collectSnapshot: false`

**New static method** — `static func rtsSmooth(snapshots:, dt:, baseProcessNoise:) -> [(x: Double, y: Double)]`:
- Takes array of `KalmanSnapshot` from forward pass
- Iterates backward from `n-2` through `0` (last frame's smoothed state = its filtered state)
- At each step k:
  1. Recomputes `x_{k+1|k} = F * x_k|k` and `P_{k+1|k} = F * P_k|k * F^T + Q(q_k, dt)`
  2. Computes smoother gain: `G_k = P_k|k * F^T * inv(P_{k+1|k})`
  3. Computes smoothed state: `x_k|N = x_k|k + G_k * (x_{k+1|N} - x_{k+1|k})`
- Returns array of smoothed `(x, y)` positions, one per frame
- **Numerical safety**: Before inverting `P_{k+1|k}`, adds epsilon (1e-10) to diagonal. If determinant is still near-zero, falls back to forward estimate for that frame.

**New static method** — `static func inverse4x4(_ m: [[Double]]) -> [[Double]]`:
- Analytical cofactor expansion for 4x4 matrix
- Returns identity matrix if determinant < 1e-15 (near-singular guard)

**Matrix helpers** — Make static:
- `stateTransitionMatrix(dt:)` — add `dt` parameter (currently uses `self.dt`)
- `processNoiseMatrix(q:, dt:)` — add explicit params (currently uses `self.adaptiveProcessNoise`, `self.dt`)
- `transpose`, `matrixMultiply`, `matrixVectorMultiply`, `matrixAdd`, `matrixSubtract` — already pure, just make `static`
- Keep instance methods as wrappers calling the static versions (avoids breaking existing callers)

### 3.2 `ios/Runner/Tracking/TrackingDataStore.swift`

**New storage** — Snapshot collection during forward pass:
```swift
/// Forward-pass Kalman snapshots per person for RTS backward smoothing
/// Key: personIndex -> array of (timestampMs, snapshot) pairs
private var bboxKalmanSnapshots: [Int: [(timestampMs: Int64, snapshot: KalmanSnapshot)]] = []

/// Forward-pass joint Kalman snapshots per person per joint for RTS backward smoothing
/// Key: personIndex -> jointName -> array of (timestampMs, snapshot) pairs
private var jointKalmanSnapshots: [Int: [String: [(timestampMs: Int64, snapshot: KalmanSnapshot)]]] = []
```

**Modified method** — `applySmoothing(to:)`:
- Bbox center (line ~388):
  ```swift
  // Current:
  let smoothedCenter = filter.update(measurement: center)
  // New:
  let (smoothedCenter, snapshot) = filter.update(measurement: center, collectSnapshot: true)
  if let snapshot = snapshot {
      bboxKalmanSnapshots[person.personIndex, default: []].append(
          (timestampMs: result.timestampMs, snapshot: snapshot)
      )
  }
  ```
- Joint Kalman filters (lines ~406-416): same pattern
  - **Note:** `PoseJoints.joints` is `[String: CodablePoint]`, not `[String: CGPoint]`. The existing code converts via `CGPoint(x: point.x, y: point.y)` and stores results via `PoseJoints(joints: [String: CGPoint])` which auto-converts back. This pattern is preserved.

**New method** — `applyRTSSmoothing(fps:)`:
```swift
/// Apply Rauch-Tung-Striebel backward smoother to all stored tracking data.
/// Replaces forward-only Kalman estimates with optimal bidirectional estimates,
/// eliminating systematic lag during fast movements.
/// Must be called after all frames are processed and before gap filling.
/// - Parameter fps: Video frame rate for dt calculation
func applyRTSSmoothing(fps: Double = 30.0) {
    let dt = 1.0 / fps

    // Phase 1: Smooth bbox center positions
    for (personIndex, snapshots) in bboxKalmanSnapshots {
        guard snapshots.count > 1 else { continue }
        let smoothedPositions = KalmanFilter2D.rtsSmooth(
            snapshots: snapshots.map(\.snapshot), dt: dt
        )
        // Overwrite stored bbox centers with smoothed values
        for (i, (timestampMs, _)) in snapshots.enumerated() {
            guard var frame = frameResults[timestampMs] else { continue }
            let updatedPeople = frame.people.map { person -> PersonTrackingResult in
                guard person.personIndex == personIndex,
                      let bbox = person.boundingBox else { return person }
                let smoothedBbox = NormalizedBoundingBox(
                    x: CGFloat(smoothedPositions[i].x),
                    y: CGFloat(smoothedPositions[i].y),
                    width: bbox.width,
                    height: bbox.height
                )
                return PersonTrackingResult(
                    personIndex: person.personIndex,
                    confidence: person.confidence,
                    boundingBox: smoothedBbox,
                    bodyOutline: person.bodyOutline,
                    pose: person.pose,
                    timestampMs: person.timestampMs,
                    identifiedPersonId: person.identifiedPersonId,
                    identifiedPersonName: person.identifiedPersonName,
                    identificationConfidence: person.identificationConfidence
                )
            }
            frameResults[timestampMs] = FrameTrackingResult(
                timestampMs: timestampMs, people: updatedPeople
            )
        }
    }

    // Phase 2: Smooth per-joint positions
    for (personIndex, jointSnapshots) in jointKalmanSnapshots {
        for (jointName, snapshots) in jointSnapshots {
            guard snapshots.count > 1 else { continue }
            let smoothedPositions = KalmanFilter2D.rtsSmooth(
                snapshots: snapshots.map(\.snapshot), dt: dt
            )
            for (i, (timestampMs, _)) in snapshots.enumerated() {
                guard var frame = frameResults[timestampMs] else { continue }
                let updatedPeople = frame.people.map { person -> PersonTrackingResult in
                    guard person.personIndex == personIndex,
                          let pose = person.pose else { return person }
                    var updatedJoints: [String: CGPoint] = [:]
                    for (name, point) in pose.joints {
                        if name == jointName {
                            updatedJoints[name] = CGPoint(
                                x: smoothedPositions[i].x,
                                y: smoothedPositions[i].y
                            )
                        } else {
                            updatedJoints[name] = CGPoint(x: point.x, y: point.y)
                        }
                    }
                    return PersonTrackingResult(
                        personIndex: person.personIndex,
                        confidence: person.confidence,
                        boundingBox: person.boundingBox,
                        bodyOutline: person.bodyOutline,
                        pose: PoseJoints(joints: updatedJoints),
                        timestampMs: person.timestampMs,
                        identifiedPersonId: person.identifiedPersonId,
                        identifiedPersonName: person.identifiedPersonName,
                        identificationConfidence: person.identificationConfidence
                    )
                }
                frameResults[timestampMs] = FrameTrackingResult(
                    timestampMs: timestampMs, people: updatedPeople
                )
            }
        }
    }

    // Phase 3: Free snapshot storage
    bboxKalmanSnapshots.removeAll()
    jointKalmanSnapshots.removeAll()
}
```

**Modified method** — `smoothBoundingBoxes()`:
- Convert from forward-only running average to **bidirectional (forward + backward + average)**:
  1. Forward pass: compute running average sizes per person per frame (existing logic, store results)
  2. Backward pass: compute running average sizes in reverse per person per frame
  3. At each frame, use the average of forward and backward estimates
  4. Apply same hard minimum floors and clamping as existing code
  5. This eliminates the bbox SIZE lag (the position lag is handled by RTS)

**Modified methods** — `clear()` and `replaceAllResults()`:
- Add cleanup: `bboxKalmanSnapshots.removeAll()` and `jointKalmanSnapshots.removeAll()`

**Deleted method** — `applyIntegralSmoothing()`:
- Remove dead code (lines 445-536). Already removed from pipeline, RTS replaces its intent entirely.

### 3.3 `ios/Runner/Tracking/TrackingService.swift`

**Modified post-processing pipeline** (lines ~512-555):

```swift
// New pipeline order:
// 1. applyRTSSmoothing(fps:)      <-- NEW: optimal bidirectional position smoothing
// 2. smoothBoundingBoxes()         <-- MODIFIED: now bidirectional for size
// 3. mergeTracksBySpatialProximity()
// 4. filterNoiseTracks()
// 5. fillTrackingGaps(maxGapFrames: 15)
// 6. applyPostTrackingMerge()
// 7. identifyTracksParallel()
```

Add before the existing `smoothBoundingBoxes()` call:
```swift
#if DEBUG
print("TrackingService: Applying RTS backward smoothing...")
#endif
let fps = Double(nominalFrameRate ?? 30)
await dataStore.applyRTSSmoothing(fps: fps)
```

### 3.4 No Changes Required

These files need **no modifications**:
- `BoundingBoxTracker.swift` — Per-frame detection logic unchanged
- `TrackingProtocol.swift` — Data structures unchanged
- `tracking_overlay.dart` — Renders whatever data it receives
- `tracking_controller.dart` — Coordinates Flutter/native, smoothing is native-side
- `motion_track.dart` — Model classes, not involved in smoothing

---

## 4. Implementation Details

### 4.1 RTS Backward Pass — Pseudocode (Corrected)

```
static func rtsSmooth(snapshots: [KalmanSnapshot], dt: Double) -> [(x: Double, y: Double)]:
    let n = snapshots.count
    guard n > 1 else:
        if n == 1: return [(snapshots[0].filteredState[0], snapshots[0].filteredState[1])]
        return []

    // Initialize: last frame's smoothed state = its filtered state
    var smoothedStates: [[Double]] = Array(repeating: [0,0,0,0], count: n)
    smoothedStates[n-1] = snapshots[n-1].filteredState

    let F = stateTransitionMatrix(dt: dt)
    let Ft = transpose(F)

    // Backward sweep: k from n-2 down to 0
    for k in stride(from: n-2, through: 0, by: -1):
        let xk = snapshots[k].filteredState           // x_k|k
        let Pk = snapshots[k].filteredCovariance       // P_k|k
        let qk = snapshots[k].adaptiveProcessNoise     // q_k

        // Recompute predicted values (eliminates indexing ambiguity):
        let xk1_pred = matrixVectorMultiply(F, xk)              // x_{k+1|k} = F * x_k|k
        let Qk = processNoiseMatrix(q: qk, dt: dt)              // Q(q_k, dt)
        let FPk = matrixMultiply(F, Pk)
        let FPkFt = matrixMultiply(FPk, Ft)
        let Pk1_pred = matrixAdd(FPkFt, Qk)                     // P_{k+1|k} = F*P_k|k*F^T + Q

        // Numerical safety: regularize before inverting
        var Pk1_reg = Pk1_pred
        for i in 0..<4: Pk1_reg[i][i] += 1e-10

        // Smoother gain: G_k = P_k|k * F^T * inv(P_{k+1|k})
        let PkFt = matrixMultiply(Pk, Ft)
        let Pk1_inv = inverse4x4(Pk1_reg)
        let G = matrixMultiply(PkFt, Pk1_inv)

        // Smoothed state: x_k|N = x_k|k + G * (x_{k+1|N} - x_{k+1|k})
        let diff = vectorSubtract(smoothedStates[k+1], xk1_pred)
        let correction = matrixVectorMultiply(G, diff)
        smoothedStates[k] = vectorAdd(xk, correction)

    return smoothedStates.map { ($0[0], $0[1]) }
```

**Key correctness properties:**
- `snapshots[k]` stores values AT frame k only (filtered state, covariance, noise)
- `x_{k+1|k}` is recomputed as `F * x_k|k` — unambiguous
- `P_{k+1|k}` is recomputed as `F * P_k|k * F^T + Q(q_k)` — uses the adaptive noise from frame k
- First frame is handled naturally — its snapshot is a valid filtered state
- Last frame's smoothed state equals its filtered state (standard RTS initialization)

### 4.2 4x4 Matrix Inverse

Analytical cofactor expansion for `inv(P_{k+1|k})`:
- The matrix is always 4x4 and symmetric positive-definite (covariance matrix)
- Fixed-size computation, no heap allocation
- Guard: if `|det| < 1e-15`, return identity (and the smoothed state falls back to filtered)
- This is faster than LU/Cholesky for such small fixed-size matrices

### 4.3 Bidirectional Bounding Box Size Smoothing

Current `smoothBoundingBoxes()` uses forward-only EMA with alpha=0.1:
```swift
avgWidth[pid] = runningW * 0.9 + bbox.width * 0.1
```

New bidirectional approach:
1. **Forward pass**: Compute forward-smoothed width/height per person per frame, store in arrays
2. **Backward pass**: Compute backward-smoothed width/height per person per frame
3. **Merge**: At each frame, final size = `(forwardSize + backwardSize) / 2`
4. **Apply**: Same hard minimum floors (0.04 width, 0.12 height), same 55% ratio enforcement, same clamping

This eliminates size lag while maintaining stability.

### 4.4 Snapshot Collection Timing

Inside `update(measurement:, collectSnapshot:)`:
```swift
func update(measurement: CGPoint, collectSnapshot: Bool = false) -> (CGPoint, KalmanSnapshot?) {
    if !isInitialized {
        state[0] = Double(measurement.x)
        state[1] = Double(measurement.y)
        state[2] = 0; state[3] = 0
        isInitialized = true
        // First frame: filtered state = initialized state, P = initial uncertainty
        let snapshot = collectSnapshot ? KalmanSnapshot(
            filteredState: state,
            filteredCovariance: P,
            adaptiveProcessNoise: adaptiveProcessNoise
        ) : nil
        return (measurement, snapshot)
    }

    predict()
    correct(measurement: measurement)

    // After correct: state = x_k|k, P = P_k|k
    let snapshot = collectSnapshot ? KalmanSnapshot(
        filteredState: state,
        filteredCovariance: P,
        adaptiveProcessNoise: adaptiveProcessNoise
    ) : nil

    return (CGPoint(x: state[0], y: state[1]), snapshot)
}
```

---

## 5. Edge Cases and Error Handling

### 5.1 Persons Appearing/Disappearing Mid-Video
Snapshot arrays are per-person, so each person's RTS runs independently on their own track segment. Person 0's snapshots are independent of person 1's.

### 5.2 Single-Frame Detections
Guard `n > 1` — for single-frame tracks, return the filtered position unchanged.

### 5.3 Very Short Tracks (2-5 frames)
RTS works correctly. With 2 frames, the smoother interpolates between the two estimates. Short tracks are usually filtered by `filterNoiseTracks()` anyway.

### 5.4 Numerical Stability
- `P_{k+1|k}` is always SPD (it's `F*P_k|k*F^T + Q` where Q has positive diagonal)
- Epsilon regularization (`+1e-10` on diagonal) before inversion
- If determinant < 1e-15 after regularization, fall back to forward estimate for that frame
- In practice, covariance matrices from Kalman filters are well-conditioned

### 5.5 Variable Frame Rate
Uses fixed `dt = 1/fps` from video asset. For variable frame rate videos, `dt` would need to be stored per-snapshot. Not needed now since all tracking uses the video's nominal frame rate.

### 5.6 CodablePoint vs CGPoint
`PoseJoints.joints` is `[String: CodablePoint]` (not `CGPoint`). The existing code in `applySmoothing()` already converts `CodablePoint` -> `CGPoint` for Kalman filter input and uses `PoseJoints(joints: [String: CGPoint])` for output (which auto-converts back). The RTS smoothing follows this same pattern.

### 5.7 NormalizedBoundingBox Center Coordinates
`NormalizedBoundingBox.x` and `.y` are CENTER coordinates, not top-left. The Kalman filter smooths these center values directly. No coordinate conversion needed.

### 5.8 Pre-existing Bug: fillGap() Coordinate Mismatch
**Note (not introduced by this design):** `fillGap()` (TrackingDataStore.swift lines 613-616) treats `bbox.x`/`bbox.y` as top-left by adding `width/2` and `height/2` to get center, but they are already center coordinates. This causes gap-filled positions to be systematically offset. This is a pre-existing bug that should be fixed separately.

---

## 6. Testing Plan

### 6.1 Unit Tests (KalmanFilter2D)

**Test: RTS eliminates lag on constant-velocity synthetic data**
- Create measurements: position = 0.01*t + noise, 100 frames
- Forward Kalman will lag systematically (mean signed error > 0)
- RTS smoothed should have mean signed error near 0
- Assert: RTS MSE < forward MSE

**Test: RTS handles sudden direction change**
- Frames 0-29: move right at 0.01/frame, frames 30-59: move left at 0.01/frame
- Assert: RTS estimate at frame 30 (direction change) is closer to true position than forward

**Test: RTS with 1 frame returns filtered estimate**

**Test: RTS with 2 frames returns reasonable interpolation**

**Test: 4x4 matrix inverse correctness**
- `M * inv(M)` = identity within 1e-10 tolerance
- Test with actual Kalman covariance matrices

**Test: Near-singular matrix returns identity (fallback)**

### 6.2 Integration Tests (TrackingDataStore)

**Test: Snapshot collection during store()**
- Store 10 frames, verify `bboxKalmanSnapshots` has entries for each person

**Test: applyRTSSmoothing() clears snapshots**
- After calling, both snapshot dictionaries are empty

**Test: applyRTSSmoothing() modifies stored positions**
- Create synthetic fast-moving track, store frames
- Apply RTS
- Verify stored positions differ from forward-only positions

**Test: Bidirectional bbox smoothing**
- Track with sudden size change → smoothed size responds equally from both directions

### 6.3 Manual Testing

**Fast dance video:** Import, run tracking, play with skeleton overlay. Verify no visible lag.

---

## 7. Performance Impact

### 7.1 Processing Time
RTS backward pass: O(n) per person per Kalman, with 4x4 matrix ops per frame.

| Component | Iterations | Time per iter | Total |
|-----------|-----------|--------------|-------|
| Bbox center (5 people, 3600 frames) | 18,000 | ~10us | ~180ms |
| 19 joints (5 people, 3600 frames) | 342,000 | ~10us | ~3.4s |
| **Total** | | | **~3.6s** |

Added to post-processing phase which already takes several seconds. Acceptable for batch.

### 7.2 Memory (Temporary)
~57 MB during RTS processing. Freed immediately after. Well within 200MB budget.

### 7.3 No Runtime Impact
Playback/scrubbing unchanged — smoother runs once during analysis. Same data types, better values.

---

## 8. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 4x4 inverse numerical instability | Low | Medium | Epsilon regularization, determinant check, fallback to forward |
| Memory spike (~57 MB) | Low | Low | Well within 200MB budget |
| Backward pass bug | Medium | High | Comprehensive synthetic-data unit tests |
| RTS over-smooths stationary periods | Low | Low | Adaptive noise from forward pass preserved |
| Pipeline order change breaks downstream | Low | Medium | RTS only changes positions; merge/filter use positions independently |

---

## 9. Summary of Changes

| File | Change Type | Lines Changed (est.) |
|------|------------|---------------------|
| `KalmanFilter.swift` | Major: Add KalmanSnapshot, rtsSmooth(), inverse4x4(), snapshot-collecting update, static matrix helpers | ~180 new |
| `TrackingDataStore.swift` | Major: Add snapshot storage, applyRTSSmoothing(), bidirectional bbox smoothing, cleanup | ~160 new, ~60 modified |
| `TrackingService.swift` | Minor: Add applyRTSSmoothing() call in pipeline | ~5 new |
| **Total** | | ~405 lines |

### Deleted Code
- `applyIntegralSmoothing()` in TrackingDataStore.swift (lines 445-536): Dead code, RTS replaces its intent

---

## 10. Review History

### Review 1 (2026-02-11) — 3 Critical Issues Found and Fixed

1. **Snapshot capture timing was mis-specified** — Design said "BEFORE predict step" but predicted values don't exist yet. Fixed: store only filtered values, recompute predicted in backward pass.

2. **Backward pass indexing was ambiguous** — `snapshots[k].predictedCovariance` was ambiguous (prediction FOR k or prediction MADE AT k?). Fixed: recompute `F * x_k|k` and `F * P_k|k * F^T + Q` in backward pass instead of storing predicted values.

3. **First-frame snapshot had no predicted values** — Frame 0 bypasses predict/correct. Fixed: with recomputation approach, frame 0's snapshot is just its initialized filtered state, which is valid.

### Medium Issues Fixed
4. **CodablePoint type noted** — `PoseJoints.joints` is `[String: CodablePoint]`, not CGPoint. Implementation must convert.
5. **Pre-existing fillGap() bug noted** — Treats center coords as top-left. Documented but not fixed by this design.
