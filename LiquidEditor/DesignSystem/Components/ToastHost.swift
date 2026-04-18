// ToastHost.swift
// LiquidEditor
//
// P1-6: App-root toast host per spec §9.9.
//
// Rules:
// - Bottom-pinned floating pill (swipe-down to dismiss).
// - Default auto-dismiss after 4s.
// - Delete-with-undo variant auto-dismisses after 8s with an amber
//   "Undo" chip that fires the provided action.
// - Error toast: red left-border + optional Retry action.
// - Max 2 visible; older toasts slide away.
// - Applied as a View modifier at the app root: `.toastHost(_ controller:)`.

import SwiftUI
import Observation

// MARK: - ToastRole

enum ToastRole: Sendable {
    case info
    case success
    case warning
    case error
}

// MARK: - ToastAction

/// Label + closure pair for the optional action chip on a toast.
struct ToastAction: Sendable {
    let label: String
    let handler: @Sendable () -> Void

    init(_ label: String, handler: @escaping @Sendable () -> Void) {
        self.label = label
        self.handler = handler
    }
}

// MARK: - ToastItem

/// A queued toast. The timeout is measured from enqueue time; the host
/// tears the toast down when it elapses or when the user swipes it away.
struct ToastItem: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let role: ToastRole
    let action: ToastAction?
    let timeout: TimeInterval

    init(
        _ message: String,
        role: ToastRole = .info,
        action: ToastAction? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.message = message
        self.role = role
        self.action = action
        self.timeout = timeout ?? (action != nil ? 8.0 : 4.0)
    }
}

// MARK: - ToastController

/// App-root observable queue. Inject one instance and call `post(_:)`.
@Observable
@MainActor
final class ToastController {

    /// Currently-visible toast stack (max 2).
    private(set) var visible: [ToastItem] = []

    /// Enqueue a new toast. If 2 are already visible, the oldest is
    /// removed to make room.
    func post(_ item: ToastItem) {
        if visible.count >= 2 {
            visible.removeFirst()
        }
        visible.append(item)
        Task { [weak self, id = item.id, timeout = item.timeout] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run {
                self?.dismiss(id: id)
            }
        }
    }

    /// Dismiss a toast by ID. Safe to call if the toast is already gone.
    func dismiss(id: UUID) {
        visible.removeAll { $0.id == id }
    }
}

// MARK: - ToastHost

/// Root-level overlay hosting up to 2 bottom-pinned toasts.
struct ToastHostView: View {

    let controller: ToastController

    var body: some View {
        VStack(spacing: 6) {
            Spacer()
            ForEach(controller.visible) { item in
                ToastRow(item: item) {
                    controller.dismiss(id: item.id)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 16)
        .animation(LiquidMotion.smooth, value: controller.visible.map(\.id))
        .allowsHitTesting(!controller.visible.isEmpty)
    }
}

// MARK: - ToastRow

private struct ToastRow: View {
    let item: ToastItem
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            roleIcon
            Text(item.message)
                .font(.footnote)
                .foregroundStyle(LiquidColors.Text.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let action = item.action {
                Button {
                    action.handler()
                    onDismiss()
                } label: {
                    Text(action.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LiquidColors.Accent.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LiquidColors.Canvas.raised, in: Capsule())
        .overlay(
            Capsule().stroke(strokeColor, lineWidth: item.role == .error ? 1 : 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 30 {
                        onDismiss()
                    } else {
                        withAnimation(LiquidMotion.snap) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.message)
    }

    private var roleIcon: some View {
        let (name, color): (String, Color) = {
            switch item.role {
            case .info:    return ("info.circle.fill", LiquidColors.Text.secondary)
            case .success: return ("checkmark.circle.fill", LiquidColors.Accent.success)
            case .warning: return ("exclamationmark.triangle.fill", LiquidColors.Accent.warning)
            case .error:   return ("xmark.octagon.fill", LiquidColors.Accent.destructive)
            }
        }()
        return Image(systemName: name)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
    }

    private var strokeColor: Color {
        item.role == .error ? LiquidColors.Accent.destructive : LiquidColors.Text.tertiary.opacity(0.2)
    }
}

// MARK: - View extension

extension View {
    /// Attach the toast host to this view (typically at the app root).
    func toastHost(_ controller: ToastController) -> some View {
        overlay(alignment: .bottom) {
            ToastHostView(controller: controller)
        }
    }
}
