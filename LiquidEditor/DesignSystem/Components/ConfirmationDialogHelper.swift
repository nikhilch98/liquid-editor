// ConfirmationDialogHelper.swift
// LiquidEditor
//
// P1-14: Standardize the pattern for destructive-action confirmations
// per spec §9.10.
//
// Usage:
//
//   @State private var pendingDeletion: DestructiveConfirmation?
//
//   ...
//   .destructiveConfirmation(item: $pendingDeletion)
//
//   // trigger:
//   pendingDeletion = DestructiveConfirmation(
//       title: "Delete this clip?",
//       actionLabel: "Delete",
//       action: { /* do it */ }
//   )
//
// Rules (per spec §9.10):
// - Use ONLY for irreversible / data-destroying actions.
// - Reversible actions must use Toast + Undo (see ToastHost) instead.
// - Title is one sentence explaining the consequence.
// - Destructive button is the .destructive role (native red).
// - Cancel button is always present.

import SwiftUI

// MARK: - DestructiveConfirmation

/// Parameters for a single destructive-action confirmation dialog.
struct DestructiveConfirmation: Identifiable, Sendable {

    /// Unique identifier so SwiftUI can diff sequential presentations.
    let id = UUID()

    /// Single-sentence title explaining what will happen.
    let title: String

    /// Optional secondary explanation (e.g., "This cannot be undone.").
    let message: String?

    /// Destructive-button label (e.g., "Delete", "Discard").
    let actionLabel: String

    /// The action to run on confirmation.
    let action: @Sendable () -> Void

    init(
        title: String,
        message: String? = nil,
        actionLabel: String,
        action: @escaping @Sendable () -> Void
    ) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.action = action
    }
}

// MARK: - View modifier

extension View {

    /// Attach the standardized destructive confirmation dialog to a view.
    ///
    /// Setting `item` non-nil presents the dialog; confirming runs
    /// `item.action` and clears `item`. On iPad the dialog anchors to
    /// the source view; on iPhone it presents as a bottom sheet (native
    /// behavior of `.confirmationDialog`).
    func destructiveConfirmation(item: Binding<DestructiveConfirmation?>) -> some View {
        confirmationDialog(
            item.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { newValue in if !newValue { item.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: item.wrappedValue
        ) { confirmation in
            Button(confirmation.actionLabel, role: .destructive) {
                confirmation.action()
                item.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                item.wrappedValue = nil
            }
        } message: { confirmation in
            if let message = confirmation.message {
                Text(message)
            }
        }
    }
}

// MARK: - Preview

#Preview("Delete confirmation") {
    struct DemoHost: View {
        @State private var pending: DestructiveConfirmation?
        var body: some View {
            VStack(spacing: 20) {
                Button("Delete clip") {
                    pending = DestructiveConfirmation(
                        title: "Delete this clip?",
                        message: "This cannot be undone.",
                        actionLabel: "Delete",
                        action: { }
                    )
                }
                .foregroundStyle(LiquidColors.Accent.destructive)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidColors.Canvas.base)
            .destructiveConfirmation(item: $pending)
        }
    }
    return DemoHost().preferredColorScheme(.dark)
}
