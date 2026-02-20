# People Library + Video Tracking Integration Design

**Author:** Claude Code
**Date:** 2026-02-02
**Status:** Final - Review 3 of 3 Complete
**Version:** 1.2.0

---

## Executive Summary

This document describes the integration between the **People Library** (persistent person management) and **Video Tracking** (real-time multi-person tracking) systems. The goal is to enable automatic identification of tracked people against the user's People library, transforming anonymous track IDs (P0, P1, P2) into recognized names (Sarah, John, Maria).

### Key Outcomes
- During video tracking, recognized people display their library names instead of generic IDs
- Cross-video consistency: Same person = same identity across all videos
- One-tap workflow to add newly tracked people to the library
- Minimal latency impact on tracking pipeline (<5ms per identification)

---

## Table of Contents

1. [Current State Analysis](#1-current-state-analysis)
2. [Integration Architecture](#2-integration-architecture)
3. [Technical Design](#3-technical-design)
4. [Edge Cases & Error Handling](#4-edge-cases--error-handling)
5. [Performance Considerations](#5-performance-considerations)
6. [Implementation Plan](#6-implementation-plan)
7. [Testing Strategy](#7-testing-strategy)
8. [Migration & Backwards Compatibility](#8-migration--backwards-compatibility)
9. [Open Questions & Decisions](#9-open-questions--decisions)

---

## 1. Current State Analysis

### 1.1 Video Tracking System

**Location:** `ios/Runner/Tracking/`

The tracking system uses YOLO-Pose + ByteTrack for multi-person tracking with ReID-based track restoration:

| Component | Purpose | Key Details |
|-----------|---------|-------------|
| `TrackingService.swift` | Flutter method channel handler | Manages sessions, coordinates analysis |
| `YOLOByteTracker.swift` | YOLO-Pose + ByteTrack tracker | Detection + association |
| `ByteTrackAssociator.swift` | Multi-frame association | Hungarian algorithm + Kalman filter |
| `ReIDExtractor.swift` | OSNet embedding extraction | 512-dim embeddings, 128x256 input |
| `TrackArchive.swift` | Lost track recovery | Archives tracks for later restoration |
| `AppearanceFeature.swift` | Embedding similarity | Cosine similarity, thresholds |

**Current Track Output:**
```swift
struct PersonTrackingResult {
    let personIndex: Int       // Generic ID: 0, 1, 2...
    let confidence: Float
    let boundingBox: NormalizedBoundingBox
    let pose: PoseJoints?
    let timestampMs: Int64
}
```

**ReID Thresholds (from AppearanceFeature.swift):**
- `reidThreshold`: 0.65 (minimum for match)
- `mediumConfidenceThreshold`: 0.68 (long-gap matching)
- `highConfidenceThreshold`: 0.78 (skip spatial checks)
- `updateAlpha`: 0.8 (EMA smoothing)

### 1.2 People Library System

**Location:** `ios/Runner/People/`, `lib/controllers/people_controller.dart`

The People Library manages persistent person identities with multiple reference images:

| Component | Purpose | Key Details |
|-----------|---------|-------------|
| `PeopleService.swift` | Detection & embedding | YOLO + OSNet for static images |
| `PeopleStorage.dart` | Persistent storage | JSON index + image files |
| `PeopleController.dart` | State management | CRUD operations, Flutter state |
| `Person` model | Person data | Name, ID, images (max 5), embeddings |

**Person Data Structure:**
```dart
class Person {
  final String id;           // UUID
  final String name;         // User-given name
  final List<PersonImage> images;  // Up to 5 reference images
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PersonImage {
  final String id;
  final String imagePath;
  final List<double> embedding;  // 512-dim OSNet embedding
  final double qualityScore;
}
```

**People Library Thresholds (from PeopleService.swift):**
- `duplicateThreshold`: 0.70 (consider same person)
- `weakMatchThreshold`: 0.55 (warning, not confident)

### 1.3 Shared Technology

Both systems use **identical OSNet 512-dimensional embeddings**:
- Same model: `OSNetReID.mlmodelc`
- Same input: 128x256 RGB person crop
- Same output: 512-dim L2-normalized vector
- Same similarity: Cosine similarity

**This is the foundation for integration** - we can directly compare embeddings from video tracking against the People library without any transformation.

### 1.4 Current Gap

| Capability | Tracking | People Library |
|------------|----------|----------------|
| Embedding extraction | ✅ Per-frame during tracking | ✅ Per-image on add |
| Cross-frame matching | ✅ Within video session | ❌ N/A |
| Cross-video matching | ❌ Session-scoped | ❌ No tracking |
| Named identification | ❌ Generic IDs only | ✅ User-assigned names |
| Persistent storage | ❌ Session only | ✅ On-disk |

---

## 2. Integration Architecture

### 2.1 Architecture Decision: Identification Layer

**Option A: Tracking-Side Integration (Recommended)**
Add identification logic to the tracking pipeline. When a track is confirmed, look up against People library.

**Pros:**
- Single point of integration
- Identification happens during tracking (not after)
- Natural place for real-time lookup
- Track already has embeddings

**Cons:**
- Couples tracking to People library
- Tracking service needs library access

**Option B: Flutter-Side Integration**
Post-process tracking results in Flutter, matching embeddings against library.

**Pros:**
- Decoupled systems
- Easier to modify without touching native code

**Cons:**
- Adds latency (round-trip to Flutter)
- Duplicates embedding comparison logic
- Harder to optimize

**Decision:** Option A - Tracking-Side Integration

### 2.2 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Flutter Layer                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  PeopleController ──────────────────────────────────────────────────┐   │
│       │                                                               │   │
│       │  loadPeople()                                                 │   │
│       ▼                                                               │   │
│  PeopleStorage ◄────── people/index.json + images/                   │   │
│       │                                                               │   │
│       │  getPeopleEmbeddings() [NEW]                                 │   │
│       ▼                                                               │   │
│  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │               Platform Channel                                    │ │   │
│  │  com.liquideditor/tracking                                        │ │   │
│  │    • setPeopleLibrary(embeddings)  [NEW]                         │ │   │
│  │    • clearPeopleLibrary()          [NEW]                         │ │   │
│  │    • getIdentifiedPersons()        [NEW]                         │ │   │
│  └─────────────────────────────────────────────────────────────────┘ │   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           iOS Native Layer                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  TrackingService                                                         │
│       │                                                                  │
│       │ handleSetPeopleLibrary() [NEW]                                  │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │              PersonIdentifier [NEW]                              │    │
│  │                                                                   │    │
│  │  • libraryEmbeddings: [PersonLibraryEntry]                       │    │
│  │  • identify(appearance: AppearanceFeature) -> IdentificationResult│    │
│  │  • updateLibrary(entries: [PersonLibraryEntry])                  │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       ▲                                                                  │
│       │ identifyTrack(track: Track) [NEW]                               │
│       │                                                                  │
│  ByteTrackAssociator                                                     │
│       │                                                                  │
│       │ update(detections:) → Track                                     │
│       │                                                                  │
│  Track (enhanced)                                                        │
│       • id: Int (session-local)                                         │
│       • identifiedPersonId: String? [NEW]                               │
│       • identifiedPersonName: String? [NEW]                             │
│       • identificationConfidence: Float? [NEW]                          │
│       • identificationAttempted: Bool [NEW]                             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Data Flow

**Initialization (App Launch):**
```
1. PeopleController.loadPeople()
2. Extract all embeddings → [PersonLibraryEntry]
3. Send to native: setPeopleLibrary(entries)
4. PersonIdentifier stores in memory for fast lookup
```

**During Video Tracking:**
```
1. ByteTrackAssociator creates/updates Track
2. Track has appearance embedding (OSNet 512-dim)
3. When track is confirmed (3+ consecutive hits):
   a. PersonIdentifier.identify(track.appearance)
   b. Compare against all library embeddings
   c. If match found (similarity ≥ threshold):
      - Set track.identifiedPersonId
      - Set track.identifiedPersonName
      - Set track.identificationConfidence
4. Return enhanced PersonTrackingResult with identification
```

**Library Updates (Person Added/Removed/Modified):**
```
1. PeopleController modifies person
2. Re-extract embeddings → [PersonLibraryEntry]
3. Send to native: setPeopleLibrary(entries) (full replace)
4. PersonIdentifier updates lookup table
5. Existing tracks are NOT re-identified (would be jarring)
```

---

## 3. Technical Design

### 3.1 New Data Structures

#### 3.1.1 PersonLibraryEntry (iOS)

```swift
/// A person from the library for identification lookup
struct PersonLibraryEntry: Sendable {
    /// Person's unique ID (from People library)
    let personId: String

    /// Person's display name
    let personName: String

    /// All embeddings for this person (from all their images)
    let embeddings: [AppearanceFeature]

    /// Best quality score among all embeddings
    let bestQualityScore: Float
}
```

#### 3.1.2 IdentificationResult (iOS)

```swift
/// Result of identifying a track against the People library
struct IdentificationResult: Sendable {
    /// Whether identification succeeded
    let isIdentified: Bool

    /// Matched person's ID (if identified)
    let personId: String?

    /// Matched person's name (if identified)
    let personName: String?

    /// Confidence of the identification (best similarity score)
    let confidence: Float

    /// Top 3 candidates for transparency/debugging
    let topCandidates: [IdentificationCandidate]
}

struct IdentificationCandidate: Sendable {
    let personId: String
    let personName: String
    let similarity: Float
}
```

#### 3.1.3 Enhanced PersonTrackingResult (iOS)

```swift
struct PersonTrackingResult: Codable, Sendable {
    let personIndex: Int              // Session-local track ID
    let confidence: Float
    let boundingBox: NormalizedBoundingBox?
    let bodyOutline: BodyOutline?
    let pose: PoseJoints?
    let timestampMs: Int64

    // NEW: Identification from People Library
    let identifiedPersonId: String?     // nil if not identified
    let identifiedPersonName: String?   // nil if not identified
    let identificationConfidence: Float? // nil if not attempted
}
```

#### 3.1.4 Flutter Data Transfer

```dart
/// Sent to native layer for identification lookup
class PersonLibraryData {
  final String personId;
  final String personName;
  final List<List<double>> embeddings;  // Multiple per person
  final double bestQualityScore;
}

/// Received from native layer in tracking results
class TrackedPersonIdentification {
  final String? personId;
  final String? personName;
  final double? confidence;
}
```

### 3.2 PersonIdentifier Service (iOS)

**Location:** `ios/Runner/Tracking/PersonIdentifier.swift` (NEW)

```swift
/// Service for identifying tracked people against the People library
/// Thread-safe via actor isolation
actor PersonIdentifier {

    /// Library entries for lookup
    private var libraryEntries: [PersonLibraryEntry] = []

    /// Cache of recent identifications (track ID -> result)
    private var identificationCache: [Int: IdentificationResult] = [:]

    // MARK: - Configuration

    /// Minimum similarity for positive identification
    private let identificationThreshold: Float = 0.68

    /// High confidence threshold (very confident match)
    private let highConfidenceThreshold: Float = 0.75

    /// Minimum quality score for track embedding to attempt identification
    private let minEmbeddingQuality: Float = 0.5

    /// Maximum candidates to return for transparency
    private let maxCandidates: Int = 3

    // MARK: - Library Management

    /// Update the library with new entries (full replace)
    func updateLibrary(_ entries: [PersonLibraryEntry]) {
        libraryEntries = entries
        identificationCache.removeAll()  // Clear stale cache
    }

    /// Clear the library (no identification possible)
    func clearLibrary() {
        libraryEntries.removeAll()
        identificationCache.removeAll()
    }

    /// Check if library is loaded
    var hasLibrary: Bool {
        !libraryEntries.isEmpty
    }

    // MARK: - Identification

    /// Identify a track against the People library
    /// - Parameters:
    ///   - trackId: Session-local track ID (for caching)
    ///   - appearance: Track's appearance embedding
    ///   - forceReidentify: If true, ignore cache and re-identify
    /// - Returns: Identification result
    func identify(
        trackId: Int,
        appearance: AppearanceFeature,
        forceReidentify: Bool = false
    ) -> IdentificationResult {

        // Check cache first (unless forced)
        if !forceReidentify, let cached = identificationCache[trackId] {
            return cached
        }

        guard !libraryEntries.isEmpty else {
            return IdentificationResult(
                isIdentified: false,
                personId: nil,
                personName: nil,
                confidence: 0,
                topCandidates: []
            )
        }

        // Skip if embedding quality is too low
        guard appearance.qualityScore >= minEmbeddingQuality else {
            return IdentificationResult(
                isIdentified: false,
                personId: nil,
                personName: nil,
                confidence: 0,
                topCandidates: []
            )
        }

        // Compare against all library entries
        var candidates: [(entry: PersonLibraryEntry, similarity: Float)] = []

        for entry in libraryEntries {
            // Find best match across all embeddings for this person
            var bestSimilarity: Float = 0

            for libraryEmbedding in entry.embeddings {
                let similarity = appearance.cosineSimilarity(with: libraryEmbedding)
                bestSimilarity = max(bestSimilarity, similarity)
            }

            candidates.append((entry, bestSimilarity))
        }

        // Sort by similarity descending
        candidates.sort { $0.similarity > $1.similarity }

        // Build top candidates list
        let topCandidates = candidates.prefix(maxCandidates).map { candidate in
            IdentificationCandidate(
                personId: candidate.entry.personId,
                personName: candidate.entry.personName,
                similarity: candidate.similarity
            )
        }

        // Check if best match exceeds threshold
        guard let bestMatch = candidates.first,
              bestMatch.similarity >= identificationThreshold else {
            let result = IdentificationResult(
                isIdentified: false,
                personId: nil,
                personName: nil,
                confidence: candidates.first?.similarity ?? 0,
                topCandidates: Array(topCandidates)
            )
            identificationCache[trackId] = result
            return result
        }

        // Additional validation: Check margin over second-best
        // If two people have very similar scores, don't identify
        if candidates.count >= 2 {
            let margin = bestMatch.similarity - candidates[1].similarity
            if margin < 0.05 && bestMatch.similarity < highConfidenceThreshold {
                // Too close to call
                let result = IdentificationResult(
                    isIdentified: false,
                    personId: nil,
                    personName: nil,
                    confidence: bestMatch.similarity,
                    topCandidates: Array(topCandidates)
                )
                identificationCache[trackId] = result
                return result
            }
        }

        // Positive identification
        let result = IdentificationResult(
            isIdentified: true,
            personId: bestMatch.entry.personId,
            personName: bestMatch.entry.personName,
            confidence: bestMatch.similarity,
            topCandidates: Array(topCandidates)
        )
        identificationCache[trackId] = result
        return result
    }

    /// Clear cache for a specific track (when track is archived)
    func clearCache(for trackId: Int) {
        identificationCache.removeValue(forKey: trackId)
    }

    /// Clear all cached identifications
    func clearAllCache() {
        identificationCache.removeAll()
    }
}
```

### 3.3 TrackingService Extensions

**Additions to `TrackingService.swift`:**

```swift
// MARK: - Person Identifier

/// Person identifier for matching tracks against People library
private let personIdentifier = PersonIdentifier()

// Add to handleMethodCall:
case "setPeopleLibrary":
    handleSetPeopleLibrary(call, result: result)

case "clearPeopleLibrary":
    handleClearPeopleLibrary(result: result)

case "getTrackIdentifications":
    handleGetTrackIdentifications(call, result: result)

// MARK: - People Library Integration

private func handleSetPeopleLibrary(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [[String: Any]] else {
        result(FlutterError(code: "INVALID_ARGS", message: "Array of person data required", details: nil))
        return
    }

    Task {
        var entries: [PersonLibraryEntry] = []

        for personData in args {
            guard let personId = personData["personId"] as? String,
                  let personName = personData["personName"] as? String,
                  let embeddingsData = personData["embeddings"] as? [[Double]],
                  let bestQuality = personData["bestQualityScore"] as? Double else {
                continue
            }

            let embeddings = embeddingsData.compactMap { embData -> AppearanceFeature? in
                let floats = embData.map { Float($0) }
                guard floats.count == AppearanceFeature.dimension else { return nil }
                return AppearanceFeature(embedding: floats)
            }

            guard !embeddings.isEmpty else { continue }

            entries.append(PersonLibraryEntry(
                personId: personId,
                personName: personName,
                embeddings: embeddings,
                bestQualityScore: Float(bestQuality)
            ))
        }

        await personIdentifier.updateLibrary(entries)

        DispatchQueue.main.async {
            result(entries.count)
        }
    }
}

private func handleClearPeopleLibrary(result: @escaping FlutterResult) {
    Task {
        await personIdentifier.clearLibrary()
        DispatchQueue.main.async {
            result(nil)
        }
    }
}
```

### 3.4 Track Enhancement

**Modifications to `Track` class in `ByteTrackAssociator.swift`:**

```swift
final class Track {
    // ... existing properties ...

    // NEW: Identification from People Library

    /// Identified person's ID from library (nil if not identified)
    var identifiedPersonId: String?

    /// Identified person's name from library (nil if not identified)
    var identifiedPersonName: String?

    /// Confidence of identification (best similarity score)
    var identificationConfidence: Float?

    /// Whether identification has been attempted
    var identificationAttempted: Bool = false
}
```

### 3.5 Platform Channel Updates

**Additions to `PeopleMethodChannel.dart`:**

```dart
class PeopleMethodChannel {
  // ... existing code ...

  /// Send People library embeddings to tracking layer for identification
  Future<int> setPeopleLibraryForTracking(List<PersonLibraryData> people) async {
    final List<Map<String, dynamic>> data = people.map((p) => {
      'personId': p.personId,
      'personName': p.personName,
      'embeddings': p.embeddings,
      'bestQualityScore': p.bestQualityScore,
    }).toList();

    final result = await _channel.invokeMethod<int>('setPeopleLibrary', data);
    return result ?? 0;
  }

  /// Clear People library from tracking layer
  Future<void> clearPeopleLibraryForTracking() async {
    await _channel.invokeMethod('clearPeopleLibrary');
  }
}
```

### 3.6 PeopleController Integration

**Additions to `PeopleController`:**

```dart
class PeopleController extends ChangeNotifier {
  // ... existing code ...

  /// Sync People library to tracking layer for identification
  Future<void> syncToTracking() async {
    if (_people.isEmpty) {
      await _methodChannel.clearPeopleLibraryForTracking();
      return;
    }

    final libraryData = _people.map((person) {
      final embeddings = person.images
          .where((img) => img.embedding.isNotEmpty)
          .map((img) => img.embedding)
          .toList();

      final bestQuality = person.images.isEmpty
          ? 0.0
          : person.images.map((i) => i.qualityScore).reduce(max);

      return PersonLibraryData(
        personId: person.id,
        personName: person.name,
        embeddings: embeddings,
        bestQualityScore: bestQuality,
      );
    }).where((p) => p.embeddings.isNotEmpty).toList();

    await _methodChannel.setPeopleLibraryForTracking(libraryData);
  }

  // Call syncToTracking() after:
  // - loadPeople() completes
  // - addPerson() completes
  // - renamePerson() completes
  // - deletePerson() completes
  // - addImageToPerson() completes
  // - removeImageFromPerson() completes
}
```

### 3.7 ByteTrackAssociator Integration (Review 2 Addition)

The identification must be integrated into the existing ByteTrack workflow. Here's where it fits:

```swift
// In ByteTrackAssociator.swift

final class ByteTrackAssociator {
    // ... existing properties ...

    /// Person identifier for library matching (injected from TrackingService)
    var personIdentifier: PersonIdentifier?

    /// Update with detections and attempt identification for new/recovered tracks
    func update(detections: [Detection], pixelBuffer: CVPixelBuffer?) -> [Track] {
        // ... existing association logic ...

        // After Step 8 (Archive dead tracks), before Step 9 (Create new tracks):
        // Identify newly confirmed tracks

        for track in tracks {
            if track.shouldAttemptIdentification,
               let identifier = personIdentifier,
               let appearance = track.appearance {
                Task {
                    let result = await identifier.identify(
                        trackId: track.id,
                        appearance: appearance
                    )
                    // Apply result synchronously (track is already confirmed)
                    track.identifiedPersonId = result.personId
                    track.identifiedPersonName = result.personName
                    track.identificationConfidence = result.confidence
                    track.identificationAttempted = true
                }
            }
        }

        // ... rest of existing logic ...
    }
}
```

**Critical Integration Points:**

1. **Inject PersonIdentifier:** TrackingService passes PersonIdentifier to ByteTrackAssociator
2. **Timing:** Identification happens after track is confirmed (3+ consecutive hits)
3. **Asynchronous:** Identification is async but track updates are applied before returning
4. **One-time:** Each track is identified once; result is cached

### 3.8 ArchivedTrack Enhancement (Review 2 Addition)

To persist identification through track archive/restore:

```swift
// In TrackArchive.swift

struct ArchivedTrack: Sendable {
    // ... existing properties ...

    // NEW: Identification persistence
    let identifiedPersonId: String?
    let identifiedPersonName: String?
    let identificationConfidence: Float?
}

// Update archive() function:
func archive(
    trackId: Int,
    appearance: AppearanceFeature,
    lastBbox: CGRect,
    // ... existing params ...
    identifiedPersonId: String? = nil,       // NEW
    identifiedPersonName: String? = nil,     // NEW
    identificationConfidence: Float? = nil   // NEW
) {
    // ... existing logic ...

    let archived = ArchivedTrack(
        // ... existing fields ...
        identifiedPersonId: identifiedPersonId,
        identifiedPersonName: identifiedPersonName,
        identificationConfidence: identificationConfidence
    )
    // ...
}
```

### 3.9 JSON Serialization for Platform Channel

The PersonTrackingResult needs proper JSON encoding for transfer to Flutter:

```swift
// In TrackingModels.swift

extension PersonTrackingResult: Encodable {
    enum CodingKeys: String, CodingKey {
        case personIndex
        case confidence
        case boundingBox
        case bodyOutline
        case pose
        case timestampMs
        case identifiedPersonId       // NEW
        case identifiedPersonName     // NEW
        case identificationConfidence // NEW
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(personIndex, forKey: .personIndex)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(boundingBox, forKey: .boundingBox)
        try container.encodeIfPresent(bodyOutline, forKey: .bodyOutline)
        try container.encodeIfPresent(pose, forKey: .pose)
        try container.encode(timestampMs, forKey: .timestampMs)
        try container.encodeIfPresent(identifiedPersonId, forKey: .identifiedPersonId)
        try container.encodeIfPresent(identifiedPersonName, forKey: .identifiedPersonName)
        try container.encodeIfPresent(identificationConfidence, forKey: .identificationConfidence)
    }
}
```

And on Flutter side:

```dart
// In lib/models/tracking_result.dart

class PersonTrackingResult {
  final int personIndex;
  final double confidence;
  final NormalizedBoundingBox? boundingBox;
  final BodyOutline? bodyOutline;
  final PoseJoints? pose;
  final int timestampMs;

  // NEW: Identification
  final String? identifiedPersonId;
  final String? identifiedPersonName;
  final double? identificationConfidence;

  /// Display name: identified name or "Person {index}"
  String get displayName =>
      identifiedPersonName ?? 'Person ${personIndex + 1}';

  factory PersonTrackingResult.fromJson(Map<String, dynamic> json) {
    return PersonTrackingResult(
      personIndex: json['personIndex'] as int,
      confidence: (json['confidence'] as num).toDouble(),
      boundingBox: json['boundingBox'] != null
          ? NormalizedBoundingBox.fromJson(json['boundingBox'])
          : null,
      bodyOutline: json['bodyOutline'] != null
          ? BodyOutline.fromJson(json['bodyOutline'])
          : null,
      pose: json['pose'] != null ? PoseJoints.fromJson(json['pose']) : null,
      timestampMs: json['timestampMs'] as int,
      identifiedPersonId: json['identifiedPersonId'] as String?,
      identifiedPersonName: json['identifiedPersonName'] as String?,
      identificationConfidence:
          (json['identificationConfidence'] as num?)?.toDouble(),
    );
  }
}
```

---

## 4. Edge Cases & Error Handling

### 4.1 Identification Edge Cases

| Edge Case | Scenario | Handling |
|-----------|----------|----------|
| **Empty Library** | No people in library | Return unidentified, skip comparisons |
| **No Embeddings** | Person has images but embedding extraction failed | Skip that person in comparisons |
| **Low Quality Track** | Track embedding quality < 0.5 | Skip identification, return unidentified |
| **Ambiguous Match** | Two people with similar similarity (margin < 0.05) | Return unidentified unless one is high-confidence (≥0.75) |
| **Close Twins/Siblings** | Extremely similar people | Requires user to distinguish; system may mis-identify |
| **Same Person, Different Appearance** | Person changed clothes, hair, etc. | Multiple reference images help; may fail if too different |
| **Partial Visibility** | Person partially occluded | Lower quality score → may skip identification |
| **Rapid Motion** | Person spinning/jumping | Embedding quality drops → retry on stable frame |
| **Track ID Collision** | Session track ID reused after archive | Cache keyed by track ID; cleared when track archived |

### 4.2 Threshold Tuning

```
SIMILARITY THRESHOLDS
├── 0.55 ─── Weak match (People library warning)
├── 0.65 ─── ReID threshold (within-video recovery)
├── 0.68 ─── Identification threshold ◄── NEW
├── 0.70 ─── Duplicate threshold (People library)
├── 0.75 ─── High confidence (skip ambiguity check) ◄── NEW
└── 0.78 ─── High confidence ReID (skip spatial)

Why 0.68 for identification?
- Higher than ReID (0.65) because we're making a NAMED claim
- Lower than duplicate (0.70) because we have multiple reference images
- User can correct mistakes; over-identification is worse than under-identification
```

### 4.3 Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| `setPeopleLibrary` fails | Invalid data format | Log error, continue without identification |
| Embedding comparison crashes | NaN/Inf in embeddings | Validate embeddings before comparison |
| Library out of sync | Flutter updated, native not notified | Always sync after any library change |
| Memory pressure | Too many people in library | Limit to 100 people; paginate if needed |
| Actor isolation violation | Cross-thread access | Use `PersonIdentifier` actor properly |

### 4.4 Concurrency Considerations

```swift
// PersonIdentifier is an actor - all access is serialized
// But we need to call it from the tracking loop which runs on sessionQueue

// In analyzeVideoAsync:
for frame in frames {
    let tracks = associator.update(detections: detections)

    // Identification in parallel (doesn't block tracking)
    await withTaskGroup(of: Void.self) { group in
        for track in tracks where !track.identificationAttempted {
            group.addTask {
                if let appearance = track.appearance {
                    let result = await self.personIdentifier.identify(
                        trackId: track.id,
                        appearance: appearance
                    )
                    // Update track (needs synchronization)
                    self.applyIdentification(track: track, result: result)
                }
            }
        }
    }
}
```

### 4.5 Multi-View Appearance Integration

**Issue Identified in Review 2:** The tracking system already has `MultiViewAppearance` for robust matching across body orientations (front, back, side). We should leverage this for identification.

```swift
// Instead of comparing against single appearance:
let similarity = appearance.cosineSimilarity(with: libraryEmbedding)

// Use multi-view comparison for better results:
let similarity = track.multiViewAppearance.bestSimilarity(with: libraryEmbedding)
```

**Rationale:** A person's front view in the video may match their back view in the library (same person, different angles). Multi-view matching handles this.

### 4.6 Track Appearance Evolution

**Issue Identified in Review 2:** Track embeddings evolve over time via EMA smoothing. When should we attempt identification?

| Scenario | Strategy |
|----------|----------|
| New track (0-3 frames) | Skip - embedding unstable |
| Confirmed track (first time) | Identify using current embedding |
| Track recovered from archive | Use archived identification if available |
| Long-running track (100+ frames) | Optional re-identify to improve confidence |

```swift
// In Track class:
var shouldAttemptIdentification: Bool {
    // Don't identify tentative tracks
    guard state == .confirmed else { return false }

    // Don't re-identify every frame
    guard !identificationAttempted else { return false }

    // Require minimum embedding quality
    guard let app = appearance, app.qualityScore >= 0.5 else { return false }

    // Require minimum track history for stable embedding
    guard kalman.hitCount >= 5 else { return false }

    return true
}
```

### 4.7 Identification Persistence

**Issue Identified in Review 2:** When a track is archived and later restored, should it keep its identification?

**Decision:** Yes, persist identification through archive/restore cycle.

```swift
// In ArchivedTrack, add:
let identifiedPersonId: String?
let identifiedPersonName: String?
let identificationConfidence: Float?

// When restoring from archive:
restoredTrack.identifiedPersonId = archived.identifiedPersonId
restoredTrack.identifiedPersonName = archived.identifiedPersonName
restoredTrack.identificationConfidence = archived.identificationConfidence
restoredTrack.identificationAttempted = archived.identifiedPersonId != nil
```

### 4.8 Library Sync Race Conditions

**Issue Identified in Review 2:** What if library is updated while tracking is in progress?

| Event | Impact | Mitigation |
|-------|--------|------------|
| Person added | New person won't be identified in current session | Acceptable - will identify in next session |
| Person renamed | Old name continues showing | Acceptable - cosmetic only |
| Person deleted | May show deleted person's name | Need to handle: mark as "Unknown" if person no longer exists |
| Embedding added | Existing tracks won't benefit | Acceptable - will improve in next session |

```swift
// When returning results, validate person still exists:
func validateIdentification(personId: String) -> Bool {
    return libraryEntries.contains { $0.personId == personId }
}

// If person was deleted, clear identification from track
if !validateIdentification(track.identifiedPersonId) {
    track.identifiedPersonId = nil
    track.identifiedPersonName = nil
    track.identificationConfidence = nil
}
```

---

## 5. Performance Considerations

### 5.1 Latency Budget

| Operation | Target | Notes |
|-----------|--------|-------|
| Single identification lookup | < 1ms | Compare against all library embeddings |
| Library update | < 10ms | Full replace, clear cache |
| Per-frame identification (all tracks) | < 5ms | Parallel identification |
| Memory overhead | < 5MB | For 100 people × 5 images × 512 floats |

### 5.2 Optimization Strategies

**1. Cache Identification Results**
```swift
// Don't re-identify every frame
private var identificationCache: [Int: IdentificationResult] = [:]

// Only re-identify when:
// - Track is new
// - Track was lost and recovered
// - forceReidentify flag is set
```

**2. Lazy Identification**
```swift
// Don't identify tentative tracks
// Wait until track is confirmed (3+ hits)
if track.state == .confirmed && !track.identificationAttempted {
    // Now identify
}
```

**3. Batch Comparisons**
```swift
// Use vDSP for batch dot products
func batchCosineSimilarity(
    query: [Float],
    library: [[Float]]
) -> [Float] {
    // Use Accelerate framework for SIMD optimization
    var results = [Float](repeating: 0, count: library.count)
    for (i, libraryEmb) in library.enumerated() {
        vDSP_dotpr(query, 1, libraryEmb, 1, &results[i], vDSP_Length(query.count))
    }
    return results
}
```

**4. Library Size Limits**
```swift
// Warn if library is too large
if libraryEntries.count > 100 {
    print("Warning: Large People library (\(libraryEntries.count) people) may impact performance")
}
```

### 5.3 Memory Profile

```
People Library in Memory (PersonIdentifier):
├── 1 person × 1 image:    512 × 4 bytes = 2 KB
├── 1 person × 5 images:   512 × 4 × 5 = 10 KB
├── 20 people × 5 images:  512 × 4 × 5 × 20 = 200 KB
├── 100 people × 5 images: 512 × 4 × 5 × 100 = 1 MB
└── Metadata overhead:     ~500 bytes/person

Total for 100 people: ~1.05 MB (well within budget)
```

---

## 6. Implementation Plan

### Phase 1: Core Infrastructure (iOS)

**Files to Create:**
- `ios/Runner/Tracking/PersonIdentifier.swift`

**Files to Modify:**
- `ios/Runner/Tracking/TrackingService.swift`
- `ios/Runner/Tracking/YOLOByteTrack/ByteTrackAssociator.swift` (Track class)
- `ios/Runner/Tracking/TrackingModels.swift` (PersonTrackingResult)

**Deliverables:**
1. PersonIdentifier actor with identify() method
2. setPeopleLibrary/clearPeopleLibrary method channel handlers
3. Enhanced Track class with identification fields
4. Enhanced PersonTrackingResult with identification data

### Phase 2: Flutter Integration

**Files to Modify:**
- `lib/controllers/people_controller.dart`
- `lib/core/people_method_channel.dart`
- `lib/models/person.dart` (add PersonLibraryData)

**Deliverables:**
1. syncToTracking() method in PeopleController
2. Platform channel methods for library sync
3. Auto-sync on library changes

### Phase 3: UI Integration

**Files to Modify:**
- `lib/views/editor/` (wherever tracking results are displayed)
- `lib/widgets/` (person label widgets)

**Deliverables:**
1. Display identified names instead of P0, P1, P2
2. Add "Add to Library" button for unidentified tracks
3. Show identification confidence (optional)

### Phase 4: Testing & Polish

**Deliverables:**
1. Unit tests for PersonIdentifier
2. Integration tests for end-to-end flow
3. Performance profiling
4. Edge case handling validation

---

## 7. Testing Strategy

### 7.1 Unit Tests

```swift
// PersonIdentifierTests.swift

func testEmptyLibraryReturnsUnidentified() async {
    let identifier = PersonIdentifier()
    let embedding = AppearanceFeature(embedding: testEmbedding)

    let result = await identifier.identify(trackId: 1, appearance: embedding)

    XCTAssertFalse(result.isIdentified)
    XCTAssertNil(result.personId)
}

func testMatchAboveThresholdIdentifies() async {
    let identifier = PersonIdentifier()
    let personEmbedding = AppearanceFeature(embedding: testEmbedding)

    await identifier.updateLibrary([
        PersonLibraryEntry(
            personId: "person-1",
            personName: "Sarah",
            embeddings: [personEmbedding],
            bestQualityScore: 0.9
        )
    ])

    // Same embedding should match perfectly
    let result = await identifier.identify(trackId: 1, appearance: personEmbedding)

    XCTAssertTrue(result.isIdentified)
    XCTAssertEqual(result.personId, "person-1")
    XCTAssertEqual(result.personName, "Sarah")
    XCTAssertGreaterThan(result.confidence, 0.99)
}

func testAmbiguousMatchReturnsUnidentified() async {
    // Two people with very similar embeddings
    let embedding1 = AppearanceFeature(embedding: testEmbedding)
    let embedding2 = AppearanceFeature(embedding: slightlyDifferentEmbedding)

    let identifier = PersonIdentifier()
    await identifier.updateLibrary([
        PersonLibraryEntry(personId: "1", personName: "Twin A", embeddings: [embedding1], bestQualityScore: 0.9),
        PersonLibraryEntry(personId: "2", personName: "Twin B", embeddings: [embedding2], bestQualityScore: 0.9)
    ])

    // Query embedding between the two
    let queryEmbedding = AppearanceFeature(embedding: midpointEmbedding)
    let result = await identifier.identify(trackId: 1, appearance: queryEmbedding)

    // Should NOT identify due to ambiguity
    XCTAssertFalse(result.isIdentified)
    XCTAssertEqual(result.topCandidates.count, 2)
}

func testCacheIsUsed() async {
    let identifier = PersonIdentifier()
    // Setup library...

    let result1 = await identifier.identify(trackId: 1, appearance: embedding)
    let result2 = await identifier.identify(trackId: 1, appearance: embedding)

    // Results should be identical (from cache)
    XCTAssertEqual(result1.personId, result2.personId)

    // Force re-identify should still work
    let result3 = await identifier.identify(trackId: 1, appearance: embedding, forceReidentify: true)
    XCTAssertEqual(result1.personId, result3.personId)
}
```

### 7.2 Integration Tests

```dart
// people_tracking_integration_test.dart

testWidgets('identified person shows name in tracking', (tester) async {
  // Setup: Add person to library
  final controller = PeopleController.shared;
  await controller.addPerson(name: 'Sarah', imagePath: sarahImagePath);

  // Wait for sync
  await Future.delayed(Duration(milliseconds: 100));

  // Start video tracking
  final trackingController = TrackingController();
  await trackingController.analyzeVideo(videoWithSarah);

  // Get tracking results
  final results = await trackingController.getResults();

  // Find Sarah's track
  final sarahTrack = results.firstWhere(
    (r) => r.identifiedPersonName == 'Sarah',
    orElse: () => throw TestFailure('Sarah not identified'),
  );

  expect(sarahTrack.identifiedPersonId, isNotNull);
  expect(sarahTrack.identificationConfidence, greaterThan(0.68));
});

testWidgets('unidentified person shows track ID', (tester) async {
  // Ensure empty library
  final controller = PeopleController.shared;
  await controller.clearAllPeople();

  // Start video tracking
  final trackingController = TrackingController();
  await trackingController.analyzeVideo(videoWithUnknownPerson);

  final results = await trackingController.getResults();

  expect(results, isNotEmpty);
  expect(results.first.identifiedPersonId, isNull);
  expect(results.first.identifiedPersonName, isNull);
});
```

### 7.3 Performance Tests

```swift
func testIdentificationPerformance() async {
    let identifier = PersonIdentifier()

    // Create 100 people with 5 embeddings each
    var entries: [PersonLibraryEntry] = []
    for i in 0..<100 {
        let embeddings = (0..<5).map { _ in
            AppearanceFeature(embedding: randomEmbedding())
        }
        entries.append(PersonLibraryEntry(
            personId: "person-\(i)",
            personName: "Person \(i)",
            embeddings: embeddings,
            bestQualityScore: 0.8
        ))
    }

    await identifier.updateLibrary(entries)

    // Time 1000 identifications
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<1000 {
        let _ = await identifier.identify(
            trackId: Int.random(in: 0..<1000),
            appearance: AppearanceFeature(embedding: randomEmbedding()),
            forceReidentify: true
        )
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    // Should complete in < 1 second (1ms per identification)
    XCTAssertLessThan(elapsed, 1.0)
}
```

---

## 8. Migration & Backwards Compatibility

### 8.1 API Compatibility

| Change | Backwards Compatible? | Notes |
|--------|----------------------|-------|
| New fields in PersonTrackingResult | ✅ Yes | Optional fields, nil if not available |
| New method channel methods | ✅ Yes | Additive, existing methods unchanged |
| Track class changes | ✅ Yes | Internal, not exposed to Flutter |
| PersonLibraryEntry | ✅ Yes | New type, doesn't affect existing code |

### 8.2 Graceful Degradation

If People library is empty or sync fails:
- Tracking continues normally
- All tracks remain unidentified (identifiedPersonId = nil)
- UI shows generic P0, P1, P2 labels
- No crashes or errors

### 8.3 Version Migration

No migration needed - this is additive functionality:
- Existing People library data unchanged
- Existing tracking data unchanged
- New identification fields are optional

---

## 9. Open Questions & Decisions

### 9.1 Resolved Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Integration location | Tracking-side (iOS) | Lower latency, natural place for embeddings |
| Identification threshold | 0.68 | Balance between precision and recall |
| Cache strategy | Per-track cache, cleared on archive | Avoid repeated computation |
| Library update strategy | Full replace | Simpler than incremental; library is small |

### 9.2 Open Questions

**Q1: Should we re-identify when track is recovered from archive?**
- Current: No (keeps original identification)
- Alternative: Yes (might have better embedding now)
- Recommendation: No - consistency is more important than accuracy improvement

**Q2: Should identification be opt-in or automatic?**
- Current: Automatic if library is loaded
- Alternative: Require explicit enable flag
- Recommendation: Automatic - it's a feature users expect

**Q3: How to handle "Add to Library" from tracking?**
- Option A: Save track's best frame + embedding
- Option B: Prompt user to select frame
- Option C: Auto-select highest quality frame
- Recommendation: Option C with Option B as fallback

**Q4: Should we support "Not this person" corrections?**
- Would require negative matching / exclusion list
- Adds significant complexity
- Recommendation: Defer to v2; users can delete wrong images

---

## Review Checklist

### Review 1 (Completed)

- [x] Architecture decision documented
- [x] Data structures defined
- [x] Core algorithms specified
- [x] Edge cases enumerated
- [x] Performance budget established
- [x] Implementation plan outlined
- [x] Testing strategy defined
- [x] Code samples validated
- [x] Threshold values verified
- [x] Memory calculations confirmed

### Review 2 (Current)

- [x] Cross-reference with existing code
- [x] Validate thread safety model
- [x] Confirm platform channel contracts
- [x] Review error handling completeness
- [x] Verify performance assumptions
- [x] Added multi-view appearance integration (Section 4.5)
- [x] Added track appearance evolution timing (Section 4.6)
- [x] Added identification persistence through archive (Section 4.7)
- [x] Added library sync race condition handling (Section 4.8)
- [x] Added ByteTrackAssociator integration details (Section 3.7)
- [x] Added detailed file change specifications

### Review 3 (Completed)

- [x] Final technical review
- [x] Documentation completeness
- [x] Implementation readiness
- [x] Risk assessment (Section 10 added)
- [x] Security considerations (Section 10.4 added)
- [x] Detailed file change manifest (Section 6.5 added)
- [x] Rollback strategy (Section 10.5 added)
- [x] Sign-off checklist (Section 11 added)

---

## Appendix A: Embedding Comparison Reference

```swift
// Cosine similarity between two 512-dim embeddings
// Both embeddings are L2-normalized, so cosine sim = dot product

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    var result: Float = 0
    vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(512))
    return result
}

// Interpretation:
// 1.0  = identical (same image)
// 0.9+ = extremely high (same person, same pose)
// 0.8  = very high (same person, different angle)
// 0.7  = high (same person, different conditions)
// 0.65 = moderate (likely same person)
// 0.5  = low (possibly same person)
// <0.5 = unlikely same person
```

## Appendix B: Threshold Derivation

The identification threshold (0.68) was chosen based on:

1. **ReID Threshold (0.65)**: The tracking system uses this for within-video recovery. Since identification is a stronger claim (assigning a NAME), we need higher confidence.

2. **Duplicate Threshold (0.70)**: The People library uses this to prevent duplicate entries. Identification can be slightly lower because:
   - We have multiple reference images to compare against
   - Users can correct mistakes by removing wrong images
   - Over-identification (calling unknown person "Sarah") is worse than under-identification

3. **Ambiguity Margin (0.05)**: If two people have similarity scores within 0.05 of each other, we don't identify. This prevents errors when people look similar.

4. **High Confidence (0.75)**: Above this threshold, we skip the ambiguity check. A 0.75+ match is strong enough to be confident even if another person scores 0.71.

---

## 10. Risk Assessment (Review 3 Addition)

### 10.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Performance regression** | Medium | High | Profile before/after; lazy identification; cache aggressively |
| **False positive identification** | Medium | Medium | Conservative threshold (0.68); ambiguity check; user can delete images |
| **Memory pressure from large library** | Low | Medium | Limit to 100 people; warn user; paginate if needed |
| **Thread safety issues** | Low | High | Use actor for PersonIdentifier; no shared mutable state |
| **Platform channel data size** | Low | Medium | Embeddings are 512 floats × 5 images × 100 people = 1MB max |

### 10.2 User Experience Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Incorrect identification shown** | Medium | High | Show confidence indicator; allow easy correction |
| **Jarring name changes during video** | Low | Medium | Don't re-identify existing tracks; keep consistent |
| **Slow tracking due to identification** | Low | High | Async identification; don't block tracking pipeline |
| **Confusion about unidentified people** | Medium | Low | Clear "Unknown Person" label; easy "Add to Library" |

### 10.3 Implementation Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Complex integration with existing code** | Medium | Medium | Minimal changes to ByteTrackAssociator; new PersonIdentifier is isolated |
| **Testing coverage gaps** | Medium | Medium | Comprehensive unit tests; integration tests; performance tests |
| **Documentation drift** | Low | Low | Update docs as part of implementation |

### 10.4 Security Considerations

| Aspect | Consideration | Status |
|--------|---------------|--------|
| **Biometric data** | Embeddings are derived from faces/bodies | Not stored externally; on-device only |
| **PII in names** | User enters person names | Stored locally in app sandbox |
| **Data transmission** | Platform channel communication | Local only; no network calls |
| **Model extraction** | OSNet model in app bundle | Standard iOS app protection applies |

**Note:** This feature processes biometric-adjacent data (appearance embeddings). While embeddings cannot be reversed to images, they can identify individuals. All processing is local; no data leaves the device.

### 10.5 Rollback Strategy

If critical issues are discovered post-implementation:

**Phase 1 Rollback (Feature Disable):**
```swift
// Add feature flag
let isIdentificationEnabled = false  // Set to true when ready

// In PersonIdentifier:
guard isIdentificationEnabled else {
    return IdentificationResult(isIdentified: false, ...)
}
```

**Phase 2 Rollback (Code Revert):**
- All new code is in separate files (PersonIdentifier.swift)
- Track class additions are optional fields (nil by default)
- PersonTrackingResult additions are optional (backward compatible)
- Revert commits in order; no migration needed

---

## 11. Implementation Sign-Off Checklist (Review 3 Addition)

Before marking implementation complete, verify:

### 11.1 Code Quality

- [ ] All new files pass `flutter analyze` with 0 issues
- [ ] All new Swift code compiles without warnings
- [ ] Unit tests for PersonIdentifier pass
- [ ] Integration tests pass

### 11.2 Performance

- [ ] Identification adds < 5ms per frame (profiled)
- [ ] Memory usage increase < 5MB with 100 people (measured)
- [ ] No frame drops during identification (visual check)

### 11.3 Functionality

- [ ] Empty library → no identification (no crash)
- [ ] Library with people → identification works
- [ ] Person deleted → old tracks show "Unknown"
- [ ] Track archived/restored → identification persists
- [ ] New track → identification attempted once track confirmed

### 11.4 User Experience

- [ ] Identified names display correctly in UI
- [ ] Unidentified people show "Person 1", "Person 2", etc.
- [ ] No jarring name changes during playback
- [ ] "Add to Library" workflow works (if implemented)

### 11.5 Documentation

- [ ] APP_LOGIC.md updated with identification flow
- [ ] FEATURES.md updated with feature status
- [ ] This design doc moved to docs/implemented/ or marked complete

---

## 12. Detailed File Change Manifest (Review 3 Addition)

### 12.1 New Files

| File | Type | Lines (Est.) | Purpose |
|------|------|--------------|---------|
| `ios/Runner/Tracking/PersonIdentifier.swift` | Swift | ~150 | Core identification service |

### 12.2 Modified Files - iOS

| File | Change Type | Estimated Changes |
|------|-------------|-------------------|
| `ios/Runner/Tracking/TrackingService.swift` | Add | +50 lines (method channel handlers) |
| `ios/Runner/Tracking/YOLOByteTrack/ByteTrackAssociator.swift` | Modify | +30 lines (Track class additions, integration point) |
| `ios/Runner/Tracking/TrackingModels.swift` | Modify | +20 lines (PersonTrackingResult fields) |
| `ios/Runner/Tracking/ReID/TrackArchive.swift` | Modify | +15 lines (identification persistence in ArchivedTrack) |
| `ios/Runner.xcodeproj/project.pbxproj` | Add | +10 lines (PersonIdentifier.swift reference) |

### 12.3 Modified Files - Flutter

| File | Change Type | Estimated Changes |
|------|-------------|-------------------|
| `lib/controllers/people_controller.dart` | Modify | +40 lines (syncToTracking method) |
| `lib/core/people_method_channel.dart` | Modify | +25 lines (setPeopleLibrary, clearPeopleLibrary) |
| `lib/models/person.dart` | Add | +15 lines (PersonLibraryData class) |
| `lib/models/tracking_result.dart` | Modify | +20 lines (identification fields, displayName) |

### 12.4 Test Files (New)

| File | Type | Purpose |
|------|------|---------|
| `ios/RunnerTests/PersonIdentifierTests.swift` | Swift Test | Unit tests for PersonIdentifier |
| `test/integration/people_tracking_integration_test.dart` | Dart Test | End-to-end integration tests |

### 12.5 Documentation Updates

| File | Change |
|------|--------|
| `docs/APP_LOGIC.md` | Add identification flow to tracking section |
| `docs/FEATURES.md` | Add "People Identification" feature with status |

---

## Appendix C: Complete Implementation Sequence

For implementers, follow this exact sequence:

```
1. Create PersonIdentifier.swift
   ├── Define PersonLibraryEntry struct
   ├── Define IdentificationResult struct
   ├── Implement PersonIdentifier actor
   └── Add to Xcode project

2. Modify TrackingService.swift
   ├── Add personIdentifier property
   ├── Add handleSetPeopleLibrary()
   ├── Add handleClearPeopleLibrary()
   └── Add method channel cases

3. Modify Track class
   ├── Add identifiedPersonId: String?
   ├── Add identifiedPersonName: String?
   ├── Add identificationConfidence: Float?
   ├── Add identificationAttempted: Bool
   └── Add shouldAttemptIdentification computed property

4. Modify ArchivedTrack struct
   ├── Add identification fields
   └── Update archive() function

5. Modify PersonTrackingResult
   ├── Add identification fields
   └── Update Encodable conformance

6. Integrate into ByteTrackAssociator
   ├── Add personIdentifier property
   └── Add identification logic after track confirmation

7. Flutter: Add PersonLibraryData
   └── In lib/models/person.dart

8. Flutter: Add platform channel methods
   └── In lib/core/people_method_channel.dart

9. Flutter: Add syncToTracking()
   └── In lib/controllers/people_controller.dart

10. Flutter: Update PersonTrackingResult
    └── Add identification fields and fromJson

11. Write tests
    ├── PersonIdentifierTests.swift
    └── people_tracking_integration_test.dart

12. Update documentation
    ├── docs/APP_LOGIC.md
    └── docs/FEATURES.md
```

---

*Document finalized after 3 rounds of review. Ready for implementation.*
