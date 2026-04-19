// TrackCollapseSwipeModifier.swift
// LiquidEditor
//
// T7-8 (Premium UI §10.3): Swipe left on a track header to collapse it,
// swipe right to expand. The modifier animates `isCollapsed` through a
// `@Binding` so the caller can shrink the track lane height to match.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Horizontal swipe-to-collapse/expand on a track header.
struct TrackCollapseSwipeModifier: ViewModifier {

    @Binding var isCollapsed: Bool

    /// Horizontal translation (in points) past which the swipe commits.
    let commitThreshold: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isCollapsed: Binding<Bool>, commitThreshold: CGFloat = 40) {
        self._isCollapsed = isCollapsed
        self.commitThreshold = commitThreshold
    }

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) >= commitThreshold else { return }
                    withAnimation(.liquid(LiquidMotion.glide, reduceMotion: reduceMotion)) {
                        if dx < 0 {
                            isCollapsed = true   // swipe left -> collapse
                        } else {
                            isCollapsed = false  // swipe right -> expand
                        }
                    }
                }
        )
    }
}

extension View {
    /// Attach horizontal swipe-to-collapse on a track header.
    func trackCollapseSwipe(isCollapsed: Binding<Bool>) -> some View {
        modifier(TrackCollapseSwipeModifier(isCollapsed: isCollapsed))
    }
}
