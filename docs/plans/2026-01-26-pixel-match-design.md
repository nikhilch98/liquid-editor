# Pixel Match System Design

**Date:** 2026-01-26
**Status:** Approved
**Purpose:** Automated Flutter UI pixel-matching system for rapid prototyping

---

## Overview

A system that iteratively matches Flutter UI to reference design images. Claude Code acts as the engine, using simple tools for screenshot capture, hot reload, and navigation.

### Primary Use Cases

1. **Rapid prototyping** (primary) - Provide any reference image, Claude iterates until UI matches
2. **Design handoff** - Match Figma/Sketch exports automatically
3. **Visual regression** - Compare against known-good baselines

### Key Design Decisions

- **Claude Code as engine** - No separate orchestration system; Claude Code handles reasoning/iteration
- **Simple tools** - Just screenshot, hot reload, navigate; Claude does the rest
- **Any image source** - Figma, sketches, screenshots, wireframes all supported
- **Claude judgment** - No pixel algorithms; Claude visually judges match quality
- **Rewind for rollback** - Use Claude Code's native rewind instead of git commits per iteration

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                  CLAUDE CODE (Already Has)                      │
├─────────────────────────────────────────────────────────────────┤
│  ✓ Read/Edit any file                                          │
│  ✓ Reasoning and iteration                                     │
│  ✓ Image understanding (multimodal)                            │
│  ✓ Code generation                                             │
└─────────────────────────────────────────────────────────────────┘
                              +
┌─────────────────────────────────────────────────────────────────┐
│                    NEW TOOLS (We Build)                         │
├─────────────────────────────────────────────────────────────────┤
│  1. screenshot.dart    - Capture current Flutter app screen     │
│  2. hot_reload.dart    - Trigger Flutter hot reload             │
│  3. navigate.dart      - Navigate app to a specific route       │
└─────────────────────────────────────────────────────────────────┘
                              +
┌─────────────────────────────────────────────────────────────────┐
│                    SKILL: /pixel-match                          │
├─────────────────────────────────────────────────────────────────┤
│  Teaches Claude Code the iteration workflow                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tool Specifications

### 1. Screenshot Tool

**Location:** `tools/pixel_match/screenshot.dart`

**Usage:**
```bash
dart run tools/pixel_match/screenshot.dart --output=.pixel_match/current.png
```

**Behavior:**
- Connects to Flutter daemon via VM service protocol
- Captures current app screen
- Saves to specified output path
- Returns exit code 0 on success

### 2. Hot Reload Tool

**Location:** `tools/pixel_match/hot_reload.dart`

**Usage:**
```bash
dart run tools/pixel_match/hot_reload.dart [--wait=500]
```

**Behavior:**
- Connects to Flutter daemon's WebSocket
- Sends `reloadSources` command
- Waits for reload confirmation
- Optional delay after reload for animations to settle

### 3. Navigation Tool

**Location:** `tools/pixel_match/navigate.dart`

**Usage:**
```bash
dart run tools/pixel_match/navigate.dart --route="/smart-edit"
dart run tools/pixel_match/navigate.dart --route="/smart-edit" --params='{"projectId":"abc"}'
dart run tools/pixel_match/navigate.dart --back
```

**Behavior:**
- Sends navigation command via debug method channel
- Requires `PixelMatchListener` registered in app (debug builds only)
- Waits for navigation to complete

### 4. App-Side Listener

**Location:** `lib/core/debug/pixel_match_listener.dart`

**Behavior:**
- Only active in debug builds (`kDebugMode`)
- Listens on `MethodChannel('com.liquideditor/pixel_match')`
- Accepts commands: `navigateTo`, `goBack`, `setState`

---

## Skill Definition

**Location:** `.claude/skills/pixel-match.md`

### Workflow

1. Parse user input (reference image, route, mode, max iterations)
2. Navigate to target route (if specified)
3. Wait for animations to settle
4. Take screenshot
5. Compare reference vs current
6. If match: success
7. If not: identify single most impactful fix
8. Apply fix, hot reload
9. Repeat based on mode (auto/checkpoint/manual)
10. Escalate if stuck

### Control Modes

- **auto** - Run until match or max iterations
- **checkpoint** - Pause every 3 iterations
- **manual** - Pause after each iteration

### Fix Strategy

- One fix per iteration
- Priority: layout → colors → typography → effects
- Use native iOS 26 Liquid Glass components

---

## Config File Format

**Location:** `pixel_match.yaml`

```yaml
defaults:
  mode: checkpoint
  max_iterations: 10
  settle_delay_ms: 500

references_dir: .pixel_match/references
screenshots_dir: .pixel_match/screenshots

targets:
  - name: home_screen
    reference: home_screen_v2.png
    route: /home

  - name: smart_edit_view
    reference: smart_edit_design.png
    route: /smart-edit
    params:
      projectId: demo_project
```

---

## Directory Structure

```
liquid-editor/
├── .pixel_match/                    # Git-ignored
│   ├── references/                  # Reference design images
│   ├── screenshots/                 # Captured screenshots
│   └── sessions/                    # Saved session state
│
├── tools/
│   └── pixel_match/
│       ├── screenshot.dart
│       ├── hot_reload.dart
│       ├── navigate.dart
│       └── README.md
│
├── lib/core/debug/
│   └── pixel_match_listener.dart
│
├── .claude/skills/
│   └── pixel-match.md
│
└── pixel_match.yaml
```

---

## Escalation Flow

**Stuck Detection Triggers:**
- 3 iterations with no visible improvement
- Same fix attempted twice
- Repeated low confidence
- Tool failures

**Escalation Response:**
1. Show what was tried
2. Show remaining visual difference
3. Offer options: alternative approach / skip / guidance / stop

---

## Implementation Checklist

### Phase 1: Core Tools
- [ ] `tools/pixel_match/screenshot.dart`
- [ ] `tools/pixel_match/hot_reload.dart`
- [ ] `tools/pixel_match/navigate.dart`

### Phase 2: App Integration
- [ ] `lib/core/debug/pixel_match_listener.dart`
- [ ] Update `lib/main.dart` (register listener)

### Phase 3: Skill & Config
- [ ] `.claude/skills/pixel-match.md`
- [ ] `pixel_match.yaml`
- [ ] `.gitignore` update

### Phase 4: Documentation
- [ ] `tools/pixel_match/README.md`
- [ ] Update `docs/FEATURES.md`

---

## Invocation Examples

```bash
# Interactive with reference image
/pixel-match reference=designs/home.png route=/home mode=auto

# From sketch
/pixel-match reference=sketch.jpg

# Batch from config
/pixel-match config=pixel_match.yaml

# Specific target from config
/pixel-match config=pixel_match.yaml target=home_screen
```
