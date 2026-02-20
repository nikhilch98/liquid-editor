# Development Workflow

---

## Standard Development Cycle

For every feature or bug fix, follow this workflow:

### 1. Research & Planning

- Understand the requirement fully
- Research existing patterns in the codebase
- Identify files that need changes (check `docs/APP_LOGIC.md` and `docs/FEATURES.md`)
- Plan approach (consider alternatives)
- Read relevant design documents in `docs/plans/`

### 2. Implementation

- Write clean, documented Swift code
- Follow existing patterns and conventions (see `docs/CODING_STANDARDS.md`)
- Use `@Observable` for ViewModels, `actor` for I/O services
- Use protocols for service abstractions
- Add comments for complex logic (explain **why**, not **what**)
- Use meaningful variable/function names

### 3. Xcodegen (If Files Added/Removed)

**CRITICAL:** Always regenerate the Xcode project after adding or removing Swift files:

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
```

This reads `project.yml` and regenerates `LiquidEditor.xcodeproj`. Forgetting this step will cause build failures due to missing file references.

### 4. Testing

- Write unit tests using Swift Testing framework (`@Suite`, `@Test`, `#expect`)
- Use `@MainActor` on test structs that access @MainActor-isolated types
- Test edge cases and error paths
- Use temporary directories for file-based tests
- Mock services using protocol abstractions

```bash
# Run all tests
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

### 5. Code Review (Self)

- Review your own changes critically
- Check against Quality Checklist (see `docs/CODING_STANDARDS.md`)
- Look for potential improvements
- Ensure consistency with codebase style
- Verify Swift 6 strict concurrency compliance (no data races)

### 6. Build & Validate

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"

# Build for iOS (MANDATORY -- catches Swift compilation errors)
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Run all tests (MANDATORY)
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```

Both commands must succeed with zero errors and zero warnings.

### 7. Performance Validation (If Performance-Critical)

- Profile with Instruments (Time Profiler, Allocations, Metal System Trace)
- Check memory usage
- Verify 60fps during animations and playback
- Ensure no main thread blocking

```bash
# Open in Xcode for Instruments profiling
open LiquidEditor.xcodeproj
# Then: Product > Profile (Cmd+I)
```

### 8. Documentation

- Update code comments
- **MANDATORY: Update project documentation:**
  - New features: Update `docs/FEATURES.md`
  - Architecture changes: Update `docs/DESIGN.md`
  - Bug fixes: Update `docs/APP_LOGIC.md`
  - Implementation details: Update `docs/APP_LOGIC.md`
  - Performance optimizations: Update `docs/PERFORMANCE.md`
  - Test coverage changes: Update `docs/TESTING.md`
- Document any limitations or TODOs

### 9. Completion

- Verify all checklist items
- **Verify documentation is updated** (required for task completion)
- Mark task as complete
- Provide summary of changes

---

## Documentation Maintenance (Living Documentation)

**CRITICAL REQUIREMENT:** Project documentation must be kept up to date with all changes, bug fixes, and lessons learned.

### When to Update Documentation

Update documentation **IMMEDIATELY** after any of these events:

- **After Every Feature Implementation** -- Update `FEATURES.md`, `DESIGN.md`, `APP_LOGIC.md`
- **After Every Bug Fix** -- Update `APP_LOGIC.md` with root cause and fix details
- **After Architecture Changes** -- Update `DESIGN.md`
- **After Performance Optimizations** -- Update `PERFORMANCE.md` with metrics
- **After Dependency Changes** -- Update `DESIGN.md`
- **After Discovering New Issues** -- Add to Known Issues in `APP_LOGIC.md`
- **After Test Coverage Changes** -- Update `TESTING.md`

### Documentation Standards

- **Be Specific:** Include file paths and exact error messages
- **Be Comprehensive:** Explain "why" behind decisions, document alternatives
- **Be Organized:** Keep sections consistent, use markdown formatting
- **Be Actionable:** Provide debugging steps, code examples, and next steps

### Enforcement

Task is **NOT** complete without documentation update. Every change must leave documentation more accurate than before.

---

## Quick Reference Commands

```bash
# Navigate to project
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"

# Regenerate Xcode project (after adding/removing files)
xcodegen generate

# Build for iOS
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Run all tests
xcodebuild test -scheme LiquidEditor \
  -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO

# Open in Xcode
open LiquidEditor.xcodeproj

# Profile with Instruments
# Xcode > Product > Profile (Cmd+I)
```

---

## Common Pitfalls

| Pitfall | Prevention |
|---------|------------|
| Forgot `xcodegen generate` after adding files | Always run after adding/removing Swift files |
| SourceKit cross-file errors | Resolve in full `xcodebuild build`, not in editor |
| Swift compiler "unable to type-check" | Break complex bodies into extracted computed properties |
| `ShapeStyle` has no `.accent` | Use `Color.accentColor` instead |
| @Observable in Task storage | Avoid storing @Observable objects in unstructured Tasks |
| PersistentTimeline is sequential | Use `startTimeOf()` for cumulative position, GapClip for absolute overlay positioning |
| TextClip style parameter | `TextClip` requires `style: TextOverlayStyle` (not optional) |

---

**Last Updated:** 2026-02-13
