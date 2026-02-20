# People Library Design Document

**Date:** 2026-02-02
**Status:** Draft (Reviewed v2)
**Author:** Claude + Nikhil

---

## 1. Overview

### 1.1 Summary

The **People** feature replaces the unused "Favourites" tab in the Project Library screen with a library for storing known individuals. Users add reference photos of people (up to 5 per person with a mandatory unique name), and the app extracts appearance embeddings using the existing YOLO + OSNet pipeline.

### 1.2 Goals

| Goal | Description |
|------|-------------|
| **Pre-identification** | Auto-recognize known people during video tracking |
| **Quick lookup** | Browse/search known individuals in the library |
| **Auto-reframe targeting** | Suggest known people when selecting tracking targets |
| **Duplicate prevention** | Detect and prevent adding the same person twice |

### 1.3 Key Decisions (from Brainstorming)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tab name | **People** | Simple, matches Apple Photos conventions |
| Images per person | **Up to 5** | Covers multiple angles for better matching |
| Guidance for angles | **Passive hint only** | "Images from different angles help improve tracking" |
| Detection method | **YOLO + OSNet** | Consistent with tracking pipeline; embeddings directly comparable |
| Duplicate threshold | **0.70 similarity** | Balanced - catches duplicates without false positives |
| Duplicate handling | **Reject or merge** | User can add to existing person or override if false positive |
| Editing capabilities | **Name + remove photos** | Can rename and remove individual photos (min 1 required) |
| Deletion | **With confirmation** | Prevents accidental data loss |
| Architecture | **New PeopleService** | Clean separation from TrackingService |
| **Name uniqueness** | **Enforced** | Prevents confusion between people |
| **Multi-person images** | **Allow selection** | User can tap to select which person to add |

### 1.4 Non-Goals (v1)

- iCloud sync
- Export/import People library
- Face recognition (using full body for consistency with tracking)
- Automatic people discovery from videos

---

## 2. Data Model

### 2.1 Dart Models

```dart
/// A known person in the People library
@immutable
class Person {
  final String id;                    // UUID v4
  final String name;                  // Mandatory, unique, user-provided
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<PersonImage> images;     // 1-5 reference images

  /// Best embedding for quick comparison (highest quality image's embedding)
  List<double> get primaryEmbedding {
    if (images.isEmpty) return [];
    // Return embedding from highest quality image
    final best = images.reduce((a, b) =>
      a.qualityScore > b.qualityScore ? a : b);
    return best.embedding;
  }

  /// All embeddings for comprehensive matching
  List<List<double>> get allEmbeddings =>
    images.map((img) => img.embedding).toList();

  /// Thumbnail path (first image)
  String get thumbnailPath => images.isNotEmpty ? images.first.imagePath : '';

  Person copyWith({
    String? name,
    DateTime? modifiedAt,
    List<PersonImage>? images,
  });

  Map<String, dynamic> toJson();
  factory Person.fromJson(Map<String, dynamic> json);
}

/// A reference image for a person
@immutable
class PersonImage {
  final String id;                    // UUID v4
  final String imagePath;             // Relative path: "People/{personId}/image_{id}.jpg"
  final List<double> embedding;       // 512-dimensional OSNet embedding
  final double qualityScore;          // 0.0-1.0, based on detection quality
  final DateTime addedAt;
  final Rect? boundingBox;            // Original detection box (for display)

  Map<String, dynamic> toJson();
  factory PersonImage.fromJson(Map<String, dynamic> json);
}

/// Result of person detection in an image
class PersonDetectionResult {
  final bool success;
  final int personCount;
  final List<DetectedPerson> people;
  final String? errorMessage;
  final PersonDetectionError? errorType;
}

enum PersonDetectionError {
  invalidImage,
  noPersonDetected,
  detectionFailed,
  embeddingFailed,
  imageTooSmall,
  imageTooDark,
}

class DetectedPerson {
  final String id;                    // Temporary ID for selection
  final Rect boundingBox;             // Normalized coordinates (0-1)
  final double confidence;            // Detection confidence
  final List<double> embedding;       // 512-dim embedding
  final double qualityScore;          // Bounding box quality
}

/// Result of duplicate check - IMPROVED
class DuplicateCheckResult {
  final bool isDuplicate;
  final String? matchedPersonId;      // ID of matched person
  final String? matchedPersonName;    // Name of matched person
  final double similarity;            // Best similarity score
  final int matchedImageIndex;        // Which image matched best

  /// For transparency - show user why we think it's a duplicate
  final List<SimilarityDetail> topMatches;  // Top 3 matches
}

class SimilarityDetail {
  final String personId;
  final String personName;
  final double similarity;
}

/// Result of adding image to existing person - NEW
class AddImageValidationResult {
  final bool isValid;
  final String? warningMessage;
  final String? betterMatchPersonId;  // If this image matches another person better
  final String? betterMatchPersonName;
  final double betterMatchSimilarity;
}
```

### 2.2 Storage Structure

```
Documents/
├── People/
│   ├── index.json                    # Quick-load index with ALL embeddings
│   ├── {person-id-1}/
│   │   ├── person.json               # Full person metadata
│   │   ├── img_001.jpg               # Reference photos (compressed for storage)
│   │   ├── img_001_full.jpg          # Original resolution (for re-extraction if needed)
│   │   ├── img_002.jpg
│   │   └── ...
│   ├── {person-id-2}/
│   │   └── ...
```

**index.json** (comprehensive - stores ALL embeddings for fast duplicate check):
```json
{
  "version": 1,
  "lastModified": "2026-02-02T10:35:00Z",
  "people": [
    {
      "id": "uuid-1",
      "name": "Sarah",
      "imageCount": 3,
      "thumbnailPath": "People/uuid-1/img_001.jpg",
      "embeddings": [
        {
          "imageId": "img-uuid-1",
          "embedding": [0.123, -0.456, ...],
          "qualityScore": 0.92
        },
        {
          "imageId": "img-uuid-2",
          "embedding": [0.124, -0.457, ...],
          "qualityScore": 0.88
        }
      ]
    }
  ]
}
```

**person.json** (full detail - loaded on demand):
```json
{
  "id": "uuid-1",
  "name": "Sarah",
  "createdAt": "2026-02-02T10:30:00Z",
  "modifiedAt": "2026-02-02T10:35:00Z",
  "images": [
    {
      "id": "img-uuid-1",
      "imagePath": "img_001.jpg",
      "embedding": [0.123, -0.456, ...],
      "qualityScore": 0.92,
      "addedAt": "2026-02-02T10:30:00Z",
      "boundingBox": {"x": 0.2, "y": 0.1, "width": 0.6, "height": 0.8}
    }
  ]
}
```

### 2.3 Storage Size Estimates

| Data | Size per Unit | Max Units | Total |
|------|---------------|-----------|-------|
| Embedding | 512 × 4 bytes = 2KB | 500 (100 people × 5) | 1MB |
| Thumbnail | ~50KB | 500 | 25MB |
| Full image | ~200KB | 500 | 100MB |
| **Total** | | | **~126MB max** |

---

## 3. Architecture

### 3.1 Component Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Flutter/Dart                               │
├─────────────────────────────────────────────────────────────────────────┤
│  ProjectLibraryView                                                     │
│  ├── Projects Tab (existing)                                            │
│  └── People Tab (NEW)                                                   │
│       ├── PeopleGridView          - Grid of person cards                │
│       ├── PeopleSearchBar         - Filter by name (NEW)                │
│       ├── AddPersonFlow           - Multi-step add flow                 │
│       │    ├── ImagePickerSheet   - Select image source                 │
│       │    ├── PersonSelectorOverlay - Select which person (if multi)   │
│       │    ├── CropConfirmSheet   - Confirm detected bounding box       │
│       │    ├── DuplicateAlert     - Handle duplicate detection          │
│       │    └── NameInputSheet     - Enter person name                   │
│       └── PersonDetailSheet       - View/edit person details            │
├─────────────────────────────────────────────────────────────────────────┤
│  PeopleController (ChangeNotifier)                                      │
│  ├── people: List<Person>         - Loaded from storage                 │
│  ├── isLoading: bool                                                    │
│  ├── searchQuery: String                                                │
│  ├── filteredPeople: List<Person> - Filtered by search                  │
│  ├── loadPeople()                 - Load from storage                   │
│  ├── addPerson()                  - Add new person (with validation)    │
│  ├── updatePersonName()           - Rename (with uniqueness check)      │
│  ├── deletePerson()               - Delete with confirmation            │
│  ├── addImageToPerson()           - Add reference image (with validation)│
│  ├── removeImageFromPerson()      - Remove reference image              │
│  └── isNameAvailable()            - Check name uniqueness               │
├─────────────────────────────────────────────────────────────────────────┤
│  PeopleStorage                                                          │
│  ├── loadIndex()                  - Load quick index                    │
│  ├── saveIndex()                  - Update index atomically             │
│  ├── loadPerson()                 - Load full person details            │
│  ├── savePerson()                 - Save person atomically              │
│  ├── deletePerson()               - Remove person directory             │
│  ├── saveImage()                  - Save & compress image               │
│  └── deleteImage()                - Remove image file                   │
├─────────────────────────────────────────────────────────────────────────┤
│  PeopleMethodChannel                                                    │
│  └── Calls to native iOS                                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                          Platform Channel
                                    │
┌─────────────────────────────────────────────────────────────────────────┐
│                              iOS/Swift                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  PeopleService (actor - thread-safe)                                    │
│  ├── detectPeople()               - YOLO detection + embedding          │
│  ├── findDuplicates()             - Smart multi-embedding comparison    │
│  ├── validateAddToExisting()      - Check if image belongs to person    │
│  └── assessImageQuality()         - Detailed quality feedback           │
├─────────────────────────────────────────────────────────────────────────┤
│  Reuses existing:                                                       │
│  ├── YOLOv8Detector               - Person detection                    │
│  ├── ReIDExtractor                - OSNet embedding extraction          │
│  └── AppearanceFeature            - Similarity computation              │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Platform Channel API

**Channel name:** `com.liquideditor.people`

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `detectPeople` | `imagePath: String` | `PersonDetectionResult` | Detect all people, extract embeddings |
| `findDuplicates` | `embedding: [Double]`, `peopleData: [{id, name, embeddings}]` | `DuplicateCheckResult` | Smart comparison against ALL embeddings per person |
| `validateAddToExisting` | `embedding: [Double]`, `targetPersonId: String`, `allPeopleData: [...]` | `AddImageValidationResult` | Check if image fits target person or matches another better |
| `assessImageQuality` | `imagePath: String` | `QualityAssessment` | Brightness, blur, size feedback |

### 3.3 File Locations

| Component | Path |
|-----------|------|
| Dart Models | `lib/models/person.dart` |
| Storage | `lib/core/people_storage.dart` |
| Controller | `lib/controllers/people_controller.dart` |
| Method Channel | `lib/services/people_method_channel.dart` |
| UI - Tab | `lib/views/library/people_tab.dart` |
| UI - Grid | `lib/views/library/people_grid_view.dart` |
| UI - Card | `lib/views/library/person_card.dart` |
| UI - Add Flow | `lib/views/library/add_person/` |
| UI - Detail | `lib/views/library/person_detail_sheet.dart` |
| iOS Service | `ios/Runner/People/PeopleService.swift` |
| iOS Channel | `ios/Runner/People/PeopleMethodChannel.swift` |

---

## 4. User Flows

### 4.1 Add New Person (Improved)

```
┌──────────────────────────────────────────────────────────────────┐
│ User taps "+" button on People tab                               │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ CupertinoActionSheet: Image Source                               │
│ ├── "Photo Library"                                              │
│ ├── "Take Photo"                                                 │
│ └── "Cancel"                                                     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ User selects/captures image                                      │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Show loading: "Analyzing image..."                               │
│ Native: detectPeople(imagePath)                                  │
│ ├── YOLO detects all people                                      │
│ ├── For each person: extract OSNet embedding                     │
│ ├── Assess image quality                                         │
│ └── Return PersonDetectionResult                                 │
└──────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
        [0 people]      [1 person]      [2+ people]
              │               │               │
              ▼               │               ▼
┌─────────────────────┐       │     ┌─────────────────────────────┐
│ Error Dialog:       │       │     │ PersonSelectorOverlay:      │
│ "No person found"   │       │     │ Show image with bounding    │
│                     │       │     │ boxes around each person.   │
│ If quality issue:   │       │     │ "Tap the person to add"     │
│ "Image too dark" or │       │     │                             │
│ "Person too small"  │       │     │ User taps one person        │
│                     │       │     │                             │
│ [Try Another Image] │       │     │ [Cancel]                    │
└─────────────────────┘       │     └─────────────────────────────┘
                              │               │
                              ▼               ▼
                    ┌─────────────────────────────┐
                    │ CropConfirmSheet:           │
                    │ Show detected bounding box  │
                    │ on the image                │
                    │                             │
                    │ "Is this the right area?"   │
                    │                             │
                    │ Quality: ★★★★☆ (Good)       │
                    │                             │
                    │ [Retake]        [Confirm]   │
                    └─────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Native: findDuplicates(embedding, allPeopleData)                 │
│ ├── For each person in library:                                  │
│ │   ├── Compare new embedding against ALL their embeddings       │
│ │   └── Record BEST match per person                             │
│ ├── Find overall best match                                      │
│ └── Return DuplicateCheckResult with top 3 matches               │
└──────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
      [No duplicate]                  [Duplicate found]
      [similarity < 0.70]             [similarity >= 0.70]
              │                               │
              ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────────────┐
│ NameInputSheet:          │    │ DuplicateAlertDialog:            │
│                          │    │                                  │
│ "Enter person's name"    │    │ "This looks like {name}"         │
│                          │    │ Similarity: 85%                  │
│ ┌──────────────────────┐ │    │                                  │
│ │ Name                 │ │    │ [Show matched image thumbnail]   │
│ └──────────────────────┘ │    │                                  │
│                          │    │ ┌────────────────────────────┐   │
│ ℹ️ Tip: Add more photos  │    │ │ Add as new photo of {name} │   │
│ from different angles    │    │ └────────────────────────────┘   │
│                          │    │ ┌────────────────────────────┐   │
│ [Cancel]   [Add Person]  │    │ │ This is a different person │   │
│                          │    │ └────────────────────────────┘   │
│ (validates uniqueness)   │    │                                  │
└──────────────────────────┘    └──────────────────────────────────┘
              │                       │                │
              │                       │                │
              ▼                       ▼                ▼
┌──────────────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Save new person:         │ │ Add to existing:│ │ NameInputSheet: │
│ 1. Create directory      │ │ 1. Check < 5 img│ │ (user override) │
│ 2. Save compressed image │ │ 2. Save image   │ │                 │
│ 3. Save person.json      │ │ 3. Update json  │ │ Note: Name must │
│ 4. Update index.json     │ │ 4. Update index │ │ be unique       │
│ 5. Refresh UI            │ │ 5. Refresh UI   │ │                 │
└──────────────────────────┘ └─────────────────┘ └─────────────────┘
```

### 4.2 Add Image to Existing Person (New Validation)

```
┌──────────────────────────────────────────────────────────────────┐
│ User is in PersonDetailSheet, taps "+" to add image              │
│ (only shown if person has < 5 images)                            │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Same image selection flow as Add New Person                      │
│ → Detection → Quality check                                      │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Native: validateAddToExisting(embedding, targetPersonId, all)    │
│ ├── Compare against target person's embeddings                   │
│ ├── Compare against ALL other people                             │
│ └── Check if another person is a BETTER match                    │
└──────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
      [Good match to       [Weak match      [Better match to
       target person]       to target]       different person]
              │               │               │
              ▼               ▼               ▼
┌─────────────────┐ ┌──────────────────┐ ┌─────────────────────────┐
│ Add image       │ │ Warning Dialog:  │ │ Warning Dialog:         │
│ directly        │ │ "Low similarity" │ │ "This looks more like   │
│                 │ │ "This might be a │ │  {otherName} (82%)      │
│                 │ │  different pose" │ │  than {targetName} (65%)│
│                 │ │                  │ │                         │
│                 │ │ [Cancel] [Add]   │ │ [Add to {other}]        │
│                 │ │                  │ │ [Add to {target} anyway]│
└─────────────────┘ └──────────────────┘ └─────────────────────────┘
```

### 4.3 View/Edit Person

```
┌──────────────────────────────────────────────────────────────────┐
│ User taps person card in grid                                    │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ PersonDetailSheet (Liquid Glass modal)                           │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ Sarah                                            [Edit Icon] │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ Reference Photos (3/5)                                           │
│                                                                  │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐                     │
│ │        │ │        │ │        │ │   +    │  ← Only if < 5      │
│ │  img1  │ │  img2  │ │  img3  │ │        │                     │
│ │   ★    │ │        │ │        │ │        │  ← Star = primary   │
│ │   ×    │ │   ×    │ │   ×    │ │        │  ← × only if > 1    │
│ └────────┘ └────────┘ └────────┘ └────────┘                     │
│                                                                  │
│ ℹ️ Images from different angles improve tracking accuracy        │
│                                                                  │
│ Added: Feb 2, 2026                                               │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │                     Delete Person                            │ │
│ └──────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 4.4 Search People

```
┌──────────────────────────────────────────────────────────────────┐
│ People Tab - Search Bar (appears on scroll down)                 │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 🔍 Search people...                                          │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ Grid filters in real-time as user types                         │
│ Case-insensitive substring match                                │
│                                                                  │
│ Empty search result: "No people matching '{query}'"             │
└──────────────────────────────────────────────────────────────────┘
```

### 4.5 Delete Person

```
┌──────────────────────────────────────────────────────────────────┐
│ User taps Delete on PersonDetailSheet                            │
│ OR long-press > "Delete" in context menu                         │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ CupertinoAlertDialog:                                            │
│                                                                  │
│ "Delete {name}?"                                                 │
│                                                                  │
│ "This will remove {name} and all {X} reference photos.           │
│  This cannot be undone."                                         │
│                                                                  │
│ [Cancel]                              [Delete] (destructive)     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. Delete person directory (atomic)                              │
│ 2. Update index.json (atomic)                                    │
│ 3. Haptic feedback (warning)                                     │
│ 4. Dismiss sheet                                                 │
│ 5. Refresh grid                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. UI Components (Liquid Glass)

### 5.1 People Tab

**Tab Bar Update:**
```dart
CNTabBar(
  items: [
    CNTabBarItem(
      label: 'Projects',
      icon: CNSymbol('square.grid.2x2'),
      activeIcon: CNSymbol('square.grid.2x2.fill'),
    ),
    CNTabBarItem(
      label: 'People',
      icon: CNSymbol('person.2'),
      activeIcon: CNSymbol('person.2.fill'),
    ),
  ],
  currentIndex: _currentTabIndex,
  onTap: (index) {
    HapticFeedback.selectionClick();
    setState(() => _currentTabIndex = index);
  },
  shrinkCentered: false,
)
```

**Empty State:**
```
┌─────────────────────────────────────────┐
│                                         │
│         [person.2.circle icon]          │
│              (64pt, grey)               │
│                                         │
│           No People Yet                 │
│                                         │
│    Add people to identify them          │
│    automatically in your videos         │
│                                         │
│        ┌─────────────────────┐          │
│        │    Add Person       │          │
│        └─────────────────────┘          │
│                                         │
└─────────────────────────────────────────┘
```

### 5.2 Person Card (Liquid Glass)

```dart
/// Person card with Liquid Glass styling
class PersonCard extends StatelessWidget {
  // Same pattern as _PremiumProjectCard
  // - ClipRRect with 16px radius
  // - BackdropFilter blur
  // - CupertinoContextMenu for long-press
  // - Gradient overlay for text readability
}
```

**Layout:**
```
┌─────────────────────────────────────────┐
│ ┌─────────────────────────────────────┐ │
│ │                                     │ │
│ │         Person's Photo              │ │
│ │         (thumbnail)                 │ │
│ │                                     │ │
│ │                           ┌───┐     │ │
│ │                           │ 3 │     │ │  ← Badge: image count
│ │                           └───┘     │ │     (if > 1)
│ └─────────────────────────────────────┘ │
│                                         │
│  Sarah                                  │  ← Name (SF Pro, 14pt, w600)
│  Added 2d ago                           │  ← Relative time (12pt, grey)
└─────────────────────────────────────────┘
```

**Context Menu Actions:**
- View Details (default)
- Add Photo
- Rename
- Delete (destructive)

### 5.3 PersonSelectorOverlay (New)

When image has multiple people, show overlay to select:

```
┌─────────────────────────────────────────┐
│                                         │
│  Select Person                     [×]  │
│                                         │
│  ┌─────────────────────────────────────┐│
│  │                                     ││
│  │    [Image with bounding boxes]      ││
│  │                                     ││
│  │   ┌─────┐           ┌─────┐        ││
│  │   │     │           │     │        ││
│  │   │  1  │           │  2  │        ││
│  │   │     │           │     │        ││
│  │   └─────┘           └─────┘        ││
│  │                                     ││
│  └─────────────────────────────────────┘│
│                                         │
│  Tap the person you want to add         │
│                                         │
└─────────────────────────────────────────┘
```

- Bounding boxes rendered with semi-transparent overlay
- Each box numbered and tappable
- Tap selects that person and continues flow

### 5.4 Quality Feedback

Show quality stars in CropConfirmSheet:

| Score | Stars | Label | Color |
|-------|-------|-------|-------|
| 0.0-0.3 | ★☆☆☆☆ | Poor | Red |
| 0.3-0.5 | ★★☆☆☆ | Fair | Orange |
| 0.5-0.7 | ★★★☆☆ | Good | Yellow |
| 0.7-0.85 | ★★★★☆ | Great | Green |
| 0.85-1.0 | ★★★★★ | Excellent | Green |

If quality < 0.5, show suggestion:
- "Try a closer photo" (if person is small)
- "Better lighting recommended" (if dark)
- "Photo is blurry" (if blurred)

### 5.5 Error Dialogs

Use `CupertinoAlertDialog` for all errors:

**No Person Detected:**
```dart
CupertinoAlertDialog(
  title: Text('No Person Detected'),
  content: Text(
    qualityIssue != null
      ? 'The image appears to be $qualityIssue. Please try a clearer photo.'
      : 'No person was found in this image. Please select a photo with a clearly visible person.'
  ),
  actions: [
    CupertinoDialogAction(
      child: Text('Try Another'),
      onPressed: () => Navigator.pop(context),
    ),
  ],
)
```

**Name Already Exists:**
```dart
CupertinoAlertDialog(
  title: Text('Name Already Used'),
  content: Text('Someone named "$name" already exists in your library. Please choose a different name.'),
  actions: [
    CupertinoDialogAction(
      child: Text('OK'),
      onPressed: () => Navigator.pop(context),
    ),
  ],
)
```

---

## 6. Native Implementation (iOS)

### 6.1 PeopleService.swift

```swift
import Foundation
import UIKit
import CoreImage

/// Thread-safe service for People library operations
actor PeopleService {

    static let shared = PeopleService()

    private let detector: YOLOv8Detector
    private let reidExtractor: ReIDExtractor

    /// Duplicate detection threshold
    private let duplicateThreshold: Float = 0.70

    /// Weak match warning threshold
    private let weakMatchThreshold: Float = 0.55

    private init() {
        self.detector = YOLOv8Detector.shared
        self.reidExtractor = ReIDExtractor.shared
    }

    // MARK: - Detection

    /// Detect all people in an image and extract embeddings
    func detectPeople(imagePath: String) async throws -> PersonDetectionResult {
        // Load image
        guard let uiImage = UIImage(contentsOfFile: imagePath),
              let ciImage = CIImage(image: uiImage) else {
            return PersonDetectionResult(
                success: false,
                errorType: .invalidImage,
                errorMessage: "Could not load image"
            )
        }

        // Assess image quality first
        let quality = assessImageQuality(ciImage)
        if !quality.isAcceptable {
            return PersonDetectionResult(
                success: false,
                errorType: quality.errorType,
                errorMessage: quality.errorMessage
            )
        }

        // Run YOLO detection
        let detections: [Detection]
        do {
            detections = try await detector.detect(in: ciImage)
        } catch {
            return PersonDetectionResult(
                success: false,
                errorType: .detectionFailed,
                errorMessage: "Detection failed: \(error.localizedDescription)"
            )
        }

        // Filter for person class (COCO class 0)
        let personDetections = detections.filter { $0.classId == 0 }

        if personDetections.isEmpty {
            return PersonDetectionResult(
                success: false,
                errorType: .noPersonDetected,
                errorMessage: "No person found in image"
            )
        }

        // Extract embedding for each person
        var people: [DetectedPerson] = []

        for (index, detection) in personDetections.enumerated() {
            let boundingBox = detection.boundingBox

            // Assess bounding box quality
            let bbQuality = reidExtractor.assessBoundingBoxQuality(boundingBox)
            guard bbQuality.isValid else { continue }

            // Extract embedding
            guard let feature = try? await reidExtractor.extractFeature(
                from: ciImage,
                boundingBox: boundingBox
            ) else { continue }

            people.append(DetectedPerson(
                id: "person_\(index)",
                boundingBox: boundingBox,
                confidence: detection.confidence,
                embedding: feature.embedding,
                qualityScore: bbQuality.qualityScore
            ))
        }

        if people.isEmpty {
            return PersonDetectionResult(
                success: false,
                errorType: .embeddingFailed,
                errorMessage: "Could not extract features from detected people"
            )
        }

        return PersonDetectionResult(
            success: true,
            personCount: people.count,
            people: people
        )
    }

    // MARK: - Duplicate Check (Improved)

    /// Smart duplicate check comparing against ALL embeddings per person
    func findDuplicates(
        newEmbedding: [Float],
        peopleData: [PersonEmbeddingData]
    ) -> DuplicateCheckResult {
        guard !peopleData.isEmpty else {
            return DuplicateCheckResult(isDuplicate: false, similarity: 0)
        }

        let newFeature = AppearanceFeature(embedding: newEmbedding)

        var matches: [(personId: String, personName: String, bestSimilarity: Float)] = []

        // For each person, find best match across ALL their embeddings
        for person in peopleData {
            var bestSimilarity: Float = 0

            for embeddingData in person.embeddings {
                let existingFeature = AppearanceFeature(embedding: embeddingData.embedding)
                let similarity = newFeature.cosineSimilarity(with: existingFeature)
                bestSimilarity = max(bestSimilarity, similarity)
            }

            matches.append((person.id, person.name, bestSimilarity))
        }

        // Sort by similarity descending
        matches.sort { $0.bestSimilarity > $1.bestSimilarity }

        // Get top 3 for transparency
        let topMatches = matches.prefix(3).map { match in
            SimilarityDetail(
                personId: match.personId,
                personName: match.personName,
                similarity: match.bestSimilarity
            )
        }

        let bestMatch = matches.first!
        let isDuplicate = bestMatch.bestSimilarity >= duplicateThreshold

        return DuplicateCheckResult(
            isDuplicate: isDuplicate,
            matchedPersonId: isDuplicate ? bestMatch.personId : nil,
            matchedPersonName: isDuplicate ? bestMatch.personName : nil,
            similarity: bestMatch.bestSimilarity,
            topMatches: Array(topMatches)
        )
    }

    // MARK: - Add to Existing Validation

    /// Validate that a new image belongs to the target person
    func validateAddToExisting(
        newEmbedding: [Float],
        targetPersonId: String,
        allPeopleData: [PersonEmbeddingData]
    ) -> AddImageValidationResult {
        let newFeature = AppearanceFeature(embedding: newEmbedding)

        var targetSimilarity: Float = 0
        var bestOtherMatch: (id: String, name: String, similarity: Float)?

        for person in allPeopleData {
            var bestSimilarity: Float = 0

            for embeddingData in person.embeddings {
                let existing = AppearanceFeature(embedding: embeddingData.embedding)
                let sim = newFeature.cosineSimilarity(with: existing)
                bestSimilarity = max(bestSimilarity, sim)
            }

            if person.id == targetPersonId {
                targetSimilarity = bestSimilarity
            } else if bestOtherMatch == nil || bestSimilarity > bestOtherMatch!.similarity {
                bestOtherMatch = (person.id, person.name, bestSimilarity)
            }
        }

        // Check if another person is a significantly better match
        if let other = bestOtherMatch,
           other.similarity > targetSimilarity + 0.1,
           other.similarity >= duplicateThreshold {
            return AddImageValidationResult(
                isValid: false,
                warningMessage: "This looks more like \(other.name)",
                betterMatchPersonId: other.id,
                betterMatchPersonName: other.name,
                betterMatchSimilarity: other.similarity
            )
        }

        // Check if weak match to target
        if targetSimilarity < weakMatchThreshold {
            return AddImageValidationResult(
                isValid: true,
                warningMessage: "Low similarity - this might be a different pose or angle"
            )
        }

        return AddImageValidationResult(isValid: true)
    }

    // MARK: - Quality Assessment

    private func assessImageQuality(_ image: CIImage) -> ImageQualityAssessment {
        let extent = image.extent

        // Check minimum size
        if extent.width < 200 || extent.height < 200 {
            return ImageQualityAssessment(
                isAcceptable: false,
                errorType: .imageTooSmall,
                errorMessage: "Image is too small. Please use a larger photo."
            )
        }

        // Check brightness using CIAreaAverage
        let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])

        if let outputImage = avgFilter?.outputImage {
            var bitmap = [UInt8](repeating: 0, count: 4)
            let context = CIContext()
            context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                          bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                          format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

            let brightness = Float(bitmap[0] + bitmap[1] + bitmap[2]) / (3.0 * 255.0)

            if brightness < 0.15 {
                return ImageQualityAssessment(
                    isAcceptable: false,
                    errorType: .imageTooDark,
                    errorMessage: "Image is too dark. Please use a well-lit photo."
                )
            }
        }

        return ImageQualityAssessment(isAcceptable: true)
    }
}

// MARK: - Supporting Types

struct PersonEmbeddingData {
    let id: String
    let name: String
    let embeddings: [EmbeddingData]
}

struct EmbeddingData {
    let imageId: String
    let embedding: [Float]
    let qualityScore: Float
}

struct PersonDetectionResult {
    let success: Bool
    let personCount: Int
    let people: [DetectedPerson]
    let errorType: PersonDetectionError?
    let errorMessage: String?

    init(success: Bool, personCount: Int = 0, people: [DetectedPerson] = [],
         errorType: PersonDetectionError? = nil, errorMessage: String? = nil) {
        self.success = success
        self.personCount = personCount
        self.people = people
        self.errorType = errorType
        self.errorMessage = errorMessage
    }
}

struct DetectedPerson {
    let id: String
    let boundingBox: CGRect
    let confidence: Float
    let embedding: [Float]
    let qualityScore: Float
}

enum PersonDetectionError: String {
    case invalidImage
    case noPersonDetected
    case detectionFailed
    case embeddingFailed
    case imageTooSmall
    case imageTooDark
}

struct DuplicateCheckResult {
    let isDuplicate: Bool
    let matchedPersonId: String?
    let matchedPersonName: String?
    let similarity: Float
    let topMatches: [SimilarityDetail]

    init(isDuplicate: Bool, matchedPersonId: String? = nil,
         matchedPersonName: String? = nil, similarity: Float = 0,
         topMatches: [SimilarityDetail] = []) {
        self.isDuplicate = isDuplicate
        self.matchedPersonId = matchedPersonId
        self.matchedPersonName = matchedPersonName
        self.similarity = similarity
        self.topMatches = topMatches
    }
}

struct SimilarityDetail {
    let personId: String
    let personName: String
    let similarity: Float
}

struct AddImageValidationResult {
    let isValid: Bool
    let warningMessage: String?
    let betterMatchPersonId: String?
    let betterMatchPersonName: String?
    let betterMatchSimilarity: Float?

    init(isValid: Bool, warningMessage: String? = nil,
         betterMatchPersonId: String? = nil, betterMatchPersonName: String? = nil,
         betterMatchSimilarity: Float? = nil) {
        self.isValid = isValid
        self.warningMessage = warningMessage
        self.betterMatchPersonId = betterMatchPersonId
        self.betterMatchPersonName = betterMatchPersonName
        self.betterMatchSimilarity = betterMatchSimilarity
    }
}

struct ImageQualityAssessment {
    let isAcceptable: Bool
    let errorType: PersonDetectionError?
    let errorMessage: String?

    init(isAcceptable: Bool, errorType: PersonDetectionError? = nil, errorMessage: String? = nil) {
        self.isAcceptable = isAcceptable
        self.errorType = errorType
        self.errorMessage = errorMessage
    }
}
```

### 6.2 PeopleMethodChannel.swift

```swift
import Flutter

final class PeopleMethodChannel: NSObject {

    static let channelName = "com.liquideditor.people"

    private var channel: FlutterMethodChannel?

    func register(with messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: Self.channelName,
            binaryMessenger: messenger
        )

        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            await handleAsync(call: call, result: result)
        }
    }

    @MainActor
    private func handleAsync(call: FlutterMethodCall, result: @escaping FlutterResult) async {
        switch call.method {
        case "detectPeople":
            await handleDetectPeople(call: call, result: result)

        case "findDuplicates":
            await handleFindDuplicates(call: call, result: result)

        case "validateAddToExisting":
            await handleValidateAddToExisting(call: call, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleDetectPeople(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) async {
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing imagePath",
                details: nil
            ))
            return
        }

        do {
            let detection = try await PeopleService.shared.detectPeople(imagePath: imagePath)
            result(detection.toDictionary())
        } catch {
            result(FlutterError(
                code: "DETECTION_FAILED",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    private func handleFindDuplicates(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) async {
        guard let args = call.arguments as? [String: Any],
              let embedding = args["embedding"] as? [Double],
              let peopleDataRaw = args["peopleData"] as? [[String: Any]] else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required arguments",
                details: nil
            ))
            return
        }

        let floatEmbedding = embedding.map { Float($0) }
        let peopleData = peopleDataRaw.compactMap { PersonEmbeddingData.fromDictionary($0) }

        let checkResult = await PeopleService.shared.findDuplicates(
            newEmbedding: floatEmbedding,
            peopleData: peopleData
        )

        result(checkResult.toDictionary())
    }

    private func handleValidateAddToExisting(
        call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) async {
        guard let args = call.arguments as? [String: Any],
              let embedding = args["embedding"] as? [Double],
              let targetPersonId = args["targetPersonId"] as? String,
              let peopleDataRaw = args["allPeopleData"] as? [[String: Any]] else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "Missing required arguments",
                details: nil
            ))
            return
        }

        let floatEmbedding = embedding.map { Float($0) }
        let peopleData = peopleDataRaw.compactMap { PersonEmbeddingData.fromDictionary($0) }

        let validation = await PeopleService.shared.validateAddToExisting(
            newEmbedding: floatEmbedding,
            targetPersonId: targetPersonId,
            allPeopleData: peopleData
        )

        result(validation.toDictionary())
    }
}

// MARK: - Dictionary Serialization

extension PersonDetectionResult {
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "success": success,
            "personCount": personCount,
            "people": people.map { $0.toDictionary() }
        ]
        if let error = errorType {
            dict["errorType"] = error.rawValue
        }
        if let msg = errorMessage {
            dict["errorMessage"] = msg
        }
        return dict
    }
}

extension DetectedPerson {
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "boundingBox": [
                "x": boundingBox.origin.x,
                "y": boundingBox.origin.y,
                "width": boundingBox.width,
                "height": boundingBox.height
            ],
            "confidence": confidence,
            "embedding": embedding,
            "qualityScore": qualityScore
        ]
    }
}

extension DuplicateCheckResult {
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "isDuplicate": isDuplicate,
            "similarity": similarity,
            "topMatches": topMatches.map { $0.toDictionary() }
        ]
        if let id = matchedPersonId {
            dict["matchedPersonId"] = id
        }
        if let name = matchedPersonName {
            dict["matchedPersonName"] = name
        }
        return dict
    }
}

extension SimilarityDetail {
    func toDictionary() -> [String: Any] {
        return [
            "personId": personId,
            "personName": personName,
            "similarity": similarity
        ]
    }
}

extension AddImageValidationResult {
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["isValid": isValid]
        if let msg = warningMessage {
            dict["warningMessage"] = msg
        }
        if let id = betterMatchPersonId {
            dict["betterMatchPersonId"] = id
        }
        if let name = betterMatchPersonName {
            dict["betterMatchPersonName"] = name
        }
        if let sim = betterMatchSimilarity {
            dict["betterMatchSimilarity"] = sim
        }
        return dict
    }
}

extension PersonEmbeddingData {
    static func fromDictionary(_ dict: [String: Any]) -> PersonEmbeddingData? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let embeddingsRaw = dict["embeddings"] as? [[String: Any]] else {
            return nil
        }

        let embeddings = embeddingsRaw.compactMap { embDict -> EmbeddingData? in
            guard let imageId = embDict["imageId"] as? String,
                  let embedding = embDict["embedding"] as? [Double],
                  let quality = embDict["qualityScore"] as? Double else {
                return nil
            }
            return EmbeddingData(
                imageId: imageId,
                embedding: embedding.map { Float($0) },
                qualityScore: Float(quality)
            )
        }

        return PersonEmbeddingData(id: id, name: name, embeddings: embeddings)
    }
}
```

---

## 7. Integration Points

### 7.1 Tracking Integration

**When:** During video tracking, after initial detections are made

**How:**
```swift
// In TrackingService, after ByteTrack creates tracks:
func identifyTracksWithPeopleLibrary(
    tracks: [Track],
    peopleLibrary: [PersonEmbeddingData]
) -> [String: String] {  // trackId -> personName
    var identifications: [String: String] = [:]

    for track in tracks {
        guard let appearance = track.multiViewAppearance.primaryEmbedding else { continue }

        // Use same logic as findDuplicates
        var bestMatch: (name: String, similarity: Float)?

        for person in peopleLibrary {
            for embData in person.embeddings {
                let existing = AppearanceFeature(embedding: embData.embedding)
                let sim = appearance.cosineSimilarity(with: existing)

                if sim >= 0.70, bestMatch == nil || sim > bestMatch!.similarity {
                    bestMatch = (person.name, sim)
                }
            }
        }

        if let match = bestMatch {
            identifications[track.id] = match.name
        }
    }

    return identifications
}
```

**UI Integration:**
- In PersonSelectionSheet, show "Sarah" instead of "Person 1" if matched
- Add checkmark badge for recognized people

### 7.2 Auto-Reframe Integration

**When:** User opens auto-reframe and selects person to track

**How:**
- Load People library
- For each detected person in video, check against library
- Show suggestion: "Is this Sarah?" with confidence percentage
- User confirms or selects different person

### 7.3 Data Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  People Library │────▶│ TrackingService │────▶│ Auto-Reframe UI │
│                 │     │                 │     │                 │
│ • Load on start │     │ • identifyTracks│     │ • Show names    │
│ • Pass to track │     │ • Return names  │     │ • Suggest match │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## 8. Atomic Storage Operations

### 8.1 Save Person (Atomic)

```dart
Future<void> savePerson(Person person) async {
  final personDir = await _getPersonDirectory(person.id);
  final tempFile = File('${personDir.path}/person_temp.json');
  final finalFile = File('${personDir.path}/person.json');

  // Write to temp file first
  await tempFile.writeAsString(jsonEncode(person.toJson()));

  // Atomic rename
  await tempFile.rename(finalFile.path);

  // Update index
  await _updateIndex();
}
```

### 8.2 Update Index (Atomic)

```dart
Future<void> _updateIndex() async {
  final peopleDir = await _peopleDirectory;
  final tempIndex = File('${peopleDir.path}/index_temp.json');
  final finalIndex = File('${peopleDir.path}/index.json');

  // Build fresh index from all person.json files
  final index = await _buildIndex();

  // Write to temp
  await tempIndex.writeAsString(jsonEncode(index));

  // Atomic rename
  await tempIndex.rename(finalIndex.path);
}
```

### 8.3 Recovery on Corruption

```dart
Future<void> loadPeople() async {
  try {
    // Try loading index
    final index = await _loadIndex();
    _people = index.people;
  } catch (e) {
    // Index corrupted - rebuild from person.json files
    debugPrint('Index corrupted, rebuilding...');
    await _rebuildIndex();
    final index = await _loadIndex();
    _people = index.people;
  }
}
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

| Test | Description |
|------|-------------|
| `Person_serialization` | JSON roundtrip preserves all fields |
| `Person_primaryEmbedding` | Returns highest quality embedding |
| `Person_allEmbeddings` | Returns all embeddings in order |
| `DuplicateCheck_exactMatch` | Same embedding → isDuplicate true |
| `DuplicateCheck_similarMatch` | 0.70+ similarity → isDuplicate true |
| `DuplicateCheck_differentPerson` | <0.70 similarity → isDuplicate false |
| `DuplicateCheck_multipleEmbeddings` | Uses best match per person |
| `NameValidation_unique` | Rejects duplicate names |
| `NameValidation_caseInsensitive` | "Sarah" and "sarah" conflict |

### 9.2 Integration Tests

| Test | Description |
|------|-------------|
| `AddPerson_singlePerson` | One person in image → succeeds |
| `AddPerson_multiplePeople_select` | Two people → can select one |
| `AddPerson_noPerson` | No person → shows error |
| `AddPerson_duplicate` | Duplicate → shows merge option |
| `AddPerson_lowQuality` | Low quality → shows warning |
| `AddImage_matchesTarget` | Image matches target person |
| `AddImage_matchesOther` | Image matches other person → warning |
| `DeletePerson_confirmation` | Requires confirmation dialog |
| `RenamePerson_unique` | New name must be unique |
| `Storage_atomicity` | Crash during save → recoverable |

### 9.3 UI Tests

| Test | Description |
|------|-------------|
| `PeopleTab_emptyState` | Shows empty state when no people |
| `PeopleTab_gridDisplay` | Shows grid with cards |
| `PeopleTab_search` | Filters people by name |
| `PersonCard_contextMenu` | Long-press shows menu |
| `AddFlow_complete` | Full add flow works |
| `PersonSelector_tap` | Can tap to select person |

---

## 10. Implementation Plan

### Phase 1: Foundation
1. Create `Person`, `PersonImage` models with serialization
2. Implement `PeopleStorage` with atomic operations
3. Create `PeopleMethodChannel` (Dart side)
4. Implement `PeopleService.swift` (actor)
5. Implement `PeopleMethodChannel.swift`
6. Register in AppDelegate

### Phase 2: Basic UI
1. Update tab bar (Favourites → People)
2. Implement empty state
3. Implement `PeopleGridView` with search
4. Implement `PersonCard` with Liquid Glass styling
5. Implement `PersonDetailSheet`

### Phase 3: Add Person Flow
1. Implement image picker action sheet
2. Implement `PersonSelectorOverlay` (multi-person selection)
3. Implement crop confirmation with quality feedback
4. Implement `findDuplicates` call and dialog
5. Implement name input with validation
6. Wire up complete add flow

### Phase 4: Edit/Delete
1. Implement rename with uniqueness check
2. Implement add image to existing person
3. Implement `validateAddToExisting` warnings
4. Implement remove image (when >1)
5. Implement delete with confirmation

### Phase 5: Polish & Testing
1. Add loading states with spinners
2. Add haptic feedback throughout
3. Write unit tests
4. Write integration tests
5. Performance testing with 100+ people

---

## 11. Open Questions (Resolved)

| Question | Resolution |
|----------|------------|
| Show confidence % when duplicate detected? | **Yes** - helps user decide if false positive |
| Camera capture for reference photos? | **Yes** - included in image picker |
| Enforce unique names? | **Yes** - prevents confusion |
| Allow multi-person image selection? | **Yes** - better UX than rejection |
| iCloud sync? | **No** - Future scope |

---

## 12. Appendix

### A. SF Symbols

| Symbol | Usage |
|--------|-------|
| `person.2` / `person.2.fill` | Tab icon |
| `person.crop.circle` | Empty state icon |
| `plus` | Add button |
| `magnifyingglass` | Search |
| `pencil` | Edit/rename |
| `trash` | Delete |
| `camera` | Camera option |
| `photo.on.rectangle` | Photo library |
| `xmark.circle.fill` | Remove image |
| `star.fill` | Primary image indicator |
| `checkmark.circle.fill` | Confirmed/matched |
| `exclamationmark.triangle` | Warning |

### B. Color Tokens

From `glass_styles.dart`:
- `AppColors.bgTop`, `AppColors.bgBottom` - Background gradient
- `AppColors.glassBorder` - Card borders
- `AppColors.textSecondary` - Secondary text
- `CupertinoColors.destructiveRed` - Delete actions
- `CupertinoColors.activeBlue` - Primary actions
- `CupertinoColors.systemYellow` - Warnings
- `CupertinoColors.systemGreen` - Success/quality good

### C. Thresholds

| Threshold | Value | Usage |
|-----------|-------|-------|
| Duplicate detection | 0.70 | Flag as same person |
| Weak match warning | 0.55 | Warn about low similarity |
| Better match delta | 0.10 | Warn if other person matches better |
| Quality - Poor | <0.30 | Show "Poor" rating |
| Quality - Fair | 0.30-0.50 | Show "Fair" rating |
| Quality - Good | 0.50-0.70 | Show "Good" rating |
| Quality - Great | 0.70-0.85 | Show "Great" rating |
| Quality - Excellent | >0.85 | Show "Excellent" rating |
