# Liquid Editor Documentation

This directory contains the comprehensive documentation for the Liquid Editor project (pure Swift/SwiftUI), organized into modular, focused documents.

## Documentation Structure

### 1. **[CODING_STANDARDS.md](CODING_STANDARDS.md)** - Coding Standards & Quality Protocol

**Purpose:** Swift coding conventions, quality checklists, and zero-tolerance policies for production code.

**Contains:**
- Swift naming conventions and style guidelines
- @Observable, @MainActor, and Swift 6 concurrency standards
- Zero-tolerance issues (force unwraps, data races, memory leaks)
- Mandatory quality checklist for every code change
- Design validation requirements (iOS 26 Liquid Glass)

**When to read:** When writing any code or reviewing code quality standards.

---

### 2. **[DESIGN.md](DESIGN.md)** - Architecture & Design Decisions

**Purpose:** High-level architecture, design patterns, and rationale behind technical decisions.

**Contains:**
- Project overview and statistics
- Build and development commands
- Project structure (complete directory tree)
- System architecture (MVVM + Coordinator + Repository)
- ServiceContainer dependency injection
- PersistentTimeline (immutable AVL tree)
- Metal GPU rendering pipeline
- State management patterns (@Observable)
- Architecture decisions and rationale

**When to read:** When making architectural changes, adding new modules, or understanding design patterns.

---

### 3. **[FEATURES.md](FEATURES.md)** - Feature Catalog & Status

**Purpose:** Complete catalog of all features, implementation details, and current status.

**Contains:**
- Feature status summary with completion indicators
- Core features: Timeline, Effects, Color Grading, Export, Audio, Tracking
- Module-by-module breakdown with Swift file locations
- Integration details and data flow
- Development recommendations and roadmap

**When to read:** When starting feature work, checking what exists, or planning new features.

---

### 4. **[APP_LOGIC.md](APP_LOGIC.md)** - Implementation Details & Technical Logic

**Purpose:** Technical implementation details, data flow, state management, and service interaction patterns.

**Contains:**
- MVVM data flow with @Observable
- Navigation via AppCoordinator
- Service interaction patterns (ServiceContainer)
- Timeline state management (PersistentTimeline)
- Playback engine lifecycle (PlaybackEngine actor)
- Composition pipeline details
- Multi-track overlay architecture

**When to read:** When understanding existing code flow, debugging issues, or implementing new service interactions.

---

### 5. **[PERFORMANCE.md](PERFORMANCE.md)** - Performance Standards

**Purpose:** Performance budgets, optimization guidelines, and profiling procedures.

**Contains:**
- Target metrics (frame rate, launch time, memory)
- Timeline Architecture V2 performance targets
- Metal shader performance notes
- CPU, Memory, GPU, and I/O optimization guidelines
- Instruments profiling procedures (Time Profiler, Metal System Trace)

**When to read:** When optimizing performance or profiling the app.

---

### 6. **[ROLES.md](ROLES.md)** - Developer Roles & Expertise

**Purpose:** Role-based development perspectives for different phases of work.

**Contains:**
- Core competencies (iOS, Swift, Vision, Metal, AVFoundation)
- Role-based perspectives for different activities
- Product Manager, Principal Engineer, Test Engineer mindsets

**When to read:** When approaching a new task to adopt the right mindset.

---

### 7. **[TESTING.md](TESTING.md)** - Testing & Validation Protocol

**Purpose:** Testing framework, patterns, commands, and validation requirements.

**Contains:**
- Swift Testing framework usage (@Suite, @Test, #expect)
- xcodebuild test commands
- Test isolation patterns (temp directories, @MainActor)
- Mock patterns for Swift protocols
- Build validation steps (mandatory after every task)
- Test coverage summary

**When to read:** When writing tests, fixing bugs, or validating changes.

---

### 8. **[WORKFLOW.md](WORKFLOW.md)** - Development Workflow

**Purpose:** Step-by-step development process from planning to completion.

**Contains:**
- Standard development cycle (research, implement, test, review, validate)
- xcodegen generate after file changes
- xcodebuild build/test commands
- Documentation maintenance requirements
- Completion criteria

**When to read:** Before starting any development task.

---

## Quick Reference Guide

| Question | File to Read |
|----------|--------------|
| **How should I write Swift code?** | [CODING_STANDARDS.md](CODING_STANDARDS.md) |
| **What architecture patterns are used?** | [DESIGN.md](DESIGN.md) |
| **What features exist in this app?** | [FEATURES.md](FEATURES.md) |
| **How does the timeline work?** | [APP_LOGIC.md](APP_LOGIC.md) |
| **What performance targets must I hit?** | [PERFORMANCE.md](PERFORMANCE.md) |
| **How do I run tests?** | [TESTING.md](TESTING.md) |
| **What is the development workflow?** | [WORKFLOW.md](WORKFLOW.md) |
| **What mindset should I adopt?** | [ROLES.md](ROLES.md) |
| **Where are design plans?** | [plans/](plans/) |

---

## Update Guidelines

When making changes to the codebase, update the appropriate documentation:

| Change Type | Update File |
|-------------|-------------|
| **New feature added** | [FEATURES.md](FEATURES.md) + [APP_LOGIC.md](APP_LOGIC.md) |
| **Architecture decision** | [DESIGN.md](DESIGN.md) |
| **Bug discovered/fixed** | [APP_LOGIC.md](APP_LOGIC.md) |
| **Performance optimization** | [PERFORMANCE.md](PERFORMANCE.md) |
| **Dependency added** | [DESIGN.md](DESIGN.md) |
| **Quality standard changed** | [CODING_STANDARDS.md](CODING_STANDARDS.md) |
| **Test coverage change** | [TESTING.md](TESTING.md) |

---

## Documentation Principles

### 1. Modularity
Each file has a single, clear purpose. No duplication across files.

### 2. Maintainability
Update only the relevant file when making changes. No need to search through a monolithic document.

### 3. Clarity
Clear separation of "what" (features), "why" (design), "how" (implementation), and "standards" (coding/testing).

### 4. Standalone
Each document can be read independently with minimal cross-references.

### 5. Living Documentation
Documentation is updated as the codebase evolves. Last updated: 2026-02-13.

---

**Last Updated:** 2026-02-13
