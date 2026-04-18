// PointerHoverEffect.swift
// LiquidEditor
//
// IP16-1 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// iPad pointer hover effects. On iPad, interactive surfaces (buttons,
// clip cells, project cards) light up with a subtle lift when the
// pointer hovers. On iPhone this is a no-op — `.hoverEffect` is harmless
// on iPhone but we only enable it on iPad to match Apple HIG.
//
// Usage:
//   Button { ... } label: { ... }
//       .pointerHover()
//
//   ClipView(...)
//       .pointerHover(.highlight)

import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - PointerHoverStyle

/// Style variants for the pointer hover effect on iPad.
///
/// Mirrors the relevant `HoverEffect` cases so callers don't need to
/// import UIKit to choose a style.
enum PointerHoverStyle: Equatable, Sendable {
    /// Subtle elevation — appropriate for buttons and pill chips.
    case lift
    /// Background highlight — appropriate for rows and cells.
    case highlight
    /// Automatic — lets the system pick the best effect for the shape.
    case automatic
}

// MARK: - PointerHoverEffect ViewModifier

/// View modifier that attaches a pointer hover effect on iPad only.
///
/// On iPhone this is a pass-through — the system already ignores
/// `.hoverEffect` when there is no pointer, but we additionally gate on
/// `FormFactor.current == .iPad` so we don't emit the modifier at all
/// on iPhone, which keeps the diff clean during UI profiling.
struct PointerHoverEffect: ViewModifier {

    // MARK: - Properties

    let style: PointerHoverStyle

    // MARK: - Body

    func body(content: Content) -> some View {
        #if os(iOS)
        if FormFactor.currentDevice == .iPad {
            switch style {
            case .lift:
                content.hoverEffect(.lift)
            case .highlight:
                content.hoverEffect(.highlight)
            case .automatic:
                content.hoverEffect(.automatic)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - View extension

extension View {
    /// Apply an iPad pointer hover effect. No-op on iPhone.
    ///
    /// - Parameter style: Hover style variant. Defaults to `.lift`.
    func pointerHover(_ style: PointerHoverStyle = .lift) -> some View {
        modifier(PointerHoverEffect(style: style))
    }
}

// MARK: - FormFactor helper (device detection)

extension FormFactor {
    /// Device-class detection used by iPad-only UI affordances.
    ///
    /// The existing `FormFactor(canvasSize:)` initializer is view-local
    /// and depends on the GeometryReader size of the editor shell —
    /// which is not what we need here. Pointer hover / drag-drop /
    /// multi-window decisions depend on the PHYSICAL DEVICE, not on
    /// the current layout canvas (a full-screen iPad in slide-over is
    /// still an iPad).
    enum Device: Equatable, Sendable {
        case iPhone
        case iPad
    }

    /// Current physical device class. Uses `UIUserInterfaceIdiom`.
    static var currentDevice: Device {
        #if os(iOS)
        // `UIDevice.current.userInterfaceIdiom` is nonisolated and safe.
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPad
        }
        return .iPhone
        #else
        return .iPhone
        #endif
    }
}
