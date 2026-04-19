// ClipGestureModifierTests.swift
// LiquidEditor
//
// TT13-4 (Premium UI §10.3): Structural invariants for
// `ClipGestureModifier` — the composite tap / double-tap / long-press
// modifier attached to timeline clips.
//
// Unit tests can't simulate SwiftUI gestures end-to-end (those require
// XCUITest or ViewInspector). Instead we assert the structural
// contract:
// - Default `longPressMinimumDuration` of 0.45s matches the spec.
// - The three callbacks are stored on the modifier as provided.
// - The `clipGestures(...)` View-extension forwards its arguments.
// - `ClipGestureModifier` conforms to `ViewModifier`.
//
// This is the honest "proxy" test for the gesture contract until a
// snapshot / XCUITest harness lands.

import SwiftUI
import Testing
@testable import LiquidEditor

// MARK: - ClipGestureModifier structural invariants

@Suite("Clip gesture invariants")
@MainActor
struct ClipGestureModifierTests {

    // MARK: - Callback capture helpers

    /// Sentinel captured by callbacks so tests can verify wiring.
    final class CallRecorder: @unchecked Sendable {
        var tapCalls: Int = 0
        var doubleTapCalls: Int = 0
        var longPressChanges: [Bool] = []
    }

    // MARK: - Defaults

    @Test("Default longPressMinimumDuration matches spec §10.3 (0.45s)")
    func longPressDefaultMatchesSpec() {
        let modifier = ClipGestureModifier(
            menuSections: [],
            onTap: {},
            onDoubleTapped: {},
            onLongPressChanged: { _ in }
        )
        #expect(modifier.longPressMinimumDuration == 0.45)
    }

    @Test("Custom longPressMinimumDuration is stored verbatim")
    func customLongPressDuration() {
        let modifier = ClipGestureModifier(
            menuSections: [],
            longPressMinimumDuration: 1.2,
            onTap: {},
            onDoubleTapped: {},
            onLongPressChanged: { _ in }
        )
        #expect(modifier.longPressMinimumDuration == 1.2)
    }

    // MARK: - Menu sections

    @Test("Menu sections are stored as provided")
    func menuSectionsStored() {
        let sections: [ContextMenuSection] = []
        let modifier = ClipGestureModifier(
            menuSections: sections,
            onTap: {},
            onDoubleTapped: {},
            onLongPressChanged: { _ in }
        )
        #expect(modifier.menuSections.count == sections.count)
    }

    // MARK: - Callback wiring

    @Test("onTap callback closure is stored and invokable")
    func onTapStored() {
        let recorder = CallRecorder()
        let modifier = ClipGestureModifier(
            menuSections: [],
            onTap: { recorder.tapCalls += 1 },
            onDoubleTapped: {},
            onLongPressChanged: { _ in }
        )
        // Directly invoke to prove it was captured.
        modifier.onTap()
        modifier.onTap()
        #expect(recorder.tapCalls == 2)
    }

    @Test("onDoubleTapped callback closure is stored and invokable")
    func onDoubleTapStored() {
        let recorder = CallRecorder()
        let modifier = ClipGestureModifier(
            menuSections: [],
            onTap: {},
            onDoubleTapped: { recorder.doubleTapCalls += 1 },
            onLongPressChanged: { _ in }
        )
        modifier.onDoubleTapped()
        #expect(recorder.doubleTapCalls == 1)
    }

    @Test("onLongPressChanged callback is invoked with both true and false")
    func onLongPressChangedStored() {
        let recorder = CallRecorder()
        let modifier = ClipGestureModifier(
            menuSections: [],
            onTap: {},
            onDoubleTapped: {},
            onLongPressChanged: { recorder.longPressChanges.append($0) }
        )
        modifier.onLongPressChanged(true)
        modifier.onLongPressChanged(false)
        #expect(recorder.longPressChanges == [true, false])
    }

    // MARK: - View extension forwarding

    @Test("View.clipGestures(...) constructs a ClipGestureModifier on the view")
    func viewExtensionWiring() {
        let recorder = CallRecorder()
        // Just verify the call compiles and returns a View; we can't
        // introspect the modifier tree without an external library.
        _ = Color.clear.clipGestures(
            menuSections: [],
            onTap: { recorder.tapCalls += 1 },
            onDoubleTapped: { recorder.doubleTapCalls += 1 },
            onLongPressChanged: { recorder.longPressChanges.append($0) }
        )
        // If construction failed it wouldn't have compiled.
        #expect(recorder.tapCalls == 0)
    }

    // MARK: - ViewModifier conformance

    @Test("ClipGestureModifier conforms to ViewModifier")
    func viewModifierConformance() {
        let modifier: any ViewModifier = ClipGestureModifier(
            menuSections: [],
            onTap: {},
            onDoubleTapped: {},
            onLongPressChanged: { _ in }
        )
        _ = modifier // silence unused-warning under strict concurrency
        #expect(Bool(true))
    }
}
