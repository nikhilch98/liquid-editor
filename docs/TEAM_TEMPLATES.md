# Team Templates for Claude Code

**Last Updated:** 2026-02-13

These are the 3 team templates for Liquid Editor development. Create the appropriate team when starting a task using `TeamCreate`.

---

## Pipeline Flow

```
Discovery → Implementation → Delivery
(research)   (build)          (validate)
```

Not every task needs all 3. See "When to Use" for each.

---

## Template 1: Discovery

**Purpose:** Research, planning, and UX analysis BEFORE writing code.

**Create with:** `TeamCreate(team_name: "discovery-{feature-name}")`

| Agent | Type | Role |
|-------|------|------|
| `leader` | general-purpose | Synthesizes findings, writes spec |
| `arch-researcher` | Explore | Explores existing codebase patterns, dependencies |
| `api-researcher` | Explore | Researches Apple APIs, checks feasibility |
| `ux-researcher` | Explore | Audits current UX, defines interaction requirements |
| `planner` | Plan | Designs implementation approach |

**All agents are read-only.** No file conflicts possible.

**Output:** Spec document with architecture plan, UX requirements, API strategy.

**When to use:**
- Before building any new feature
- When evaluating technical approaches (Metal vs CoreImage, etc.)
- Before complex refactors
- When a feature touches user interaction patterns

**Skip when:**
- Bug fix with obvious cause
- Single-file changes
- Documentation-only work

---

## Template 2: Implementation

**Purpose:** Building features with clear file ownership to prevent conflicts.

**Create with:** `TeamCreate(team_name: "impl-{feature-name}")`

| Agent | Type | Owns | Role |
|-------|------|------|------|
| `leader` | general-purpose | `App/`, `Navigation/`, `project.yml` | Orchestrates, resolves conflicts, integrates |
| `core-engineer` | general-purpose | `Services/`, `Models/`, `Metal/`, `Repositories/`, `Extensions/` | Business logic, AVFoundation, Metal |
| `ui-engineer` | general-purpose | `Views/`, `ViewModels/`, `DesignSystem/`, `Timeline/` | SwiftUI views, animations, Liquid Glass |
| `ux-reviewer` | general-purpose | Reviews `Views/`, `Timeline/` | Audits UI quality (see checklist below) |
| `test-engineer` | general-purpose | `LiquidEditorTests/` | Tests, mocks, edge cases |

### UX Reviewer Checklist (Applied to Every View)

- [ ] Responsive layout: iPhone SE (375pt) → Pro Max (430pt) → iPad
- [ ] Touch targets >= 44pt
- [ ] VoiceOver labels and traits on all interactive elements
- [ ] Dynamic Type scaling (all text sizes)
- [ ] Safe area handling (notch, home indicator, dynamic island)
- [ ] Haptic feedback consistency (selection, impact, notification)
- [ ] Empty states, error states, loading states
- [ ] Left-handed usability for timeline interactions
- [ ] Color contrast ratios (WCAG AA minimum)
- [ ] Keyboard and external display support

### Execution Order

```
core-engineer + ui-engineer (parallel)
        ↓
  ux-reviewer (audits UI)
        ↓
  test-engineer (writes tests)
        ↓
  leader (integrates)
```

**Critical Rule:** One agent per directory. If two agents need the same file, leader handles it.

**When to use:**
- Any feature that touches 3+ files
- Features with both logic and UI components
- Anything that needs accessibility review

**Skip when:**
- Single-file fix
- Test-only changes
- Research/exploration tasks

---

## Template 3: Delivery

**Purpose:** Validation, documentation, and shipping readiness.

**Create with:** `TeamCreate(team_name: "deliver-{feature-name}")`

| Agent | Type | Role |
|-------|------|------|
| `leader` | general-purpose | Coordinates, final sign-off |
| `build-validator` | Bash | `xcodegen generate` + `xcodebuild build`, zero warnings |
| `test-runner` | Bash | Full test suite, coverage check |
| `doc-updater` | general-purpose | `docs/`, `analysis/`, `FEATURES.md` |

### Validation Gates (ALL Must Pass)

- [ ] `xcodegen generate` succeeds
- [ ] `xcodebuild build` — zero errors, zero warnings
- [ ] `xcodebuild test` — 100% pass rate
- [ ] Swift 6 strict concurrency — zero concurrency warnings
- [ ] Documentation updated for all changed behavior
- [ ] Codebase analysis updated for all modified Swift files
- [ ] No regressions in existing features

### Build Commands

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"

# Build validation
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj \
  -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Test validation
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.0' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

**When to use:**
- After implementation team completes work
- Before marking any task as done
- Release prep / App Store submission

**Skip when:**
- Documentation-only changes (just update docs directly)
- Research tasks (no code to validate)

---

## Quick Reference: Which Team for Which Task

| Task Type | Teams Needed |
|-----------|-------------|
| New feature (complex) | Discovery → Implementation → Delivery |
| New feature (simple) | Implementation → Delivery |
| Bug fix (complex) | Discovery → Implementation → Delivery |
| Bug fix (simple) | Single agent + Delivery |
| Refactor | Discovery → Implementation → Delivery |
| Performance optimization | Discovery → Implementation → Delivery |
| API research | Discovery only |
| Documentation update | Single agent (no team) |
| Single file edit | Single agent (no team) |
