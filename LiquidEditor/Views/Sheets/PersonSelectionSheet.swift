// PersonSelectionSheet.swift
// LiquidEditor
//
// Bottom sheet for selecting which tracked persons to include
// in auto-reframe or tracking operations. Shows person thumbnails
// in a horizontal scrolling grid with selection state.

import SwiftUI

// MARK: - DetectedPersonItem

/// Data for a single detected person shown in the selection sheet.
///
/// Lightweight display model separate from the full `PersonTrackingResult`
/// to keep the view layer decoupled from tracking internals.
struct DetectedPersonItem: Identifiable, Sendable {
    /// Person index (stable across frames).
    let personIndex: Int

    /// Display label (e.g., "Person 1" or identified name).
    let label: String

    /// Optional thumbnail image data.
    let thumbnail: Data?

    var id: Int { personIndex }
}

// MARK: - PersonSelectionSheet

/// Sheet showing detected persons with thumbnails for selection.
///
/// Features:
/// - Horizontal scrolling person cards with thumbnails
/// - Select all / deselect all buttons
/// - Confirm button with count display
/// - Empty state when no persons detected
struct PersonSelectionSheet: View {

    // MARK: - Properties

    /// Detected persons to display.
    let persons: [DetectedPersonItem]

    /// Currently selected person indices.
    @Binding var selectedIndices: Set<Int>

    /// Callback when selection is confirmed.
    var onConfirm: (() -> Void)?

    /// Callback to dismiss the sheet.
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        if persons.isEmpty {
            emptyState
        } else {
            selectionContent
        }
    }

    // MARK: - Selection Content

    private var selectionContent: some View {
        VStack(spacing: 0) {
            // Drag indicator
            dragHandle

            // Title row
            titleRow

            // Person cards
            personCardsRow

            // Confirm button
            confirmButton
        }
        .background(.ultraThinMaterial)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 0)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: LiquidSpacing.cornerXLarge,
                topTrailingRadius: LiquidSpacing.cornerXLarge
            )
        )
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: LiquidSpacing.xxs)
            .fill(Color.white.opacity(0.3))
            .frame(width: 40, height: 4)
            .padding(.top, LiquidSpacing.md)
            .accessibilityHidden(true)
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack {
            Image(systemName: "person.2")
                .foregroundStyle(.cyan)
                .font(.system(size: LiquidSpacing.xxl))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                Text("Select Persons to Track")
                    .font(LiquidTypography.title3)
                    .foregroundStyle(.white)

                Text("Tap to select/deselect")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Select all
            selectionButton(label: "All", icon: "checkmark.square") {
                selectedIndices = Set(persons.map(\.personIndex))
            }
            .accessibilityLabel("Select all persons")

            // Deselect all
            selectionButton(label: "None", icon: "square") {
                selectedIndices.removeAll()
            }
            .accessibilityLabel("Deselect all persons")
        }
        .padding(LiquidSpacing.lg)
    }

    private func selectionButton(
        label: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(LiquidTypography.caption)
                .foregroundStyle(Color(UIColor.systemGray2))
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs + 2)
        }
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Person Cards

    private var personCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.md) {
                ForEach(persons) { person in
                    personCard(person)
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
        }
        .frame(height: 140)
    }

    private func personCard(_ person: DetectedPersonItem) -> some View {
        let isSelected = selectedIndices.contains(person.personIndex)
        return Button {
            toggleSelection(person.personIndex)
        } label: {
            VStack(spacing: LiquidSpacing.sm) {
                // Thumbnail or placeholder
                thumbnailView(person: person)

                // Label
                HStack(spacing: LiquidSpacing.xs) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(LiquidTypography.footnote)
                            .foregroundStyle(.cyan)
                    }

                    Text(person.label)
                        .font(LiquidTypography.footnote)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .cyan : Color(UIColor.systemGray2))
                        .lineLimit(1)
                }
            }
            .frame(width: 90)
            .padding(.vertical, LiquidSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                    .fill(isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                    .stroke(
                        isSelected ? Color.cyan : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .accessibilityLabel("\(person.label), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") this person for tracking")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func thumbnailView(person: DetectedPersonItem) -> some View {
        Group {
            if let data = person.thumbnail,
               let uiImage = UIImage(data: data)
            {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(UIColor.systemGray4)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: LiquidSpacing.xxxl - 2))
                            .foregroundStyle(Color(UIColor.systemGray3))
                    }
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onConfirm?()
            onDismiss?()
            dismiss()
        } label: {
            Text(confirmButtonTitle)
                .font(LiquidTypography.calloutMedium)
                .foregroundStyle(selectedIndices.isEmpty ? Color.secondary : Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpacing.md + 2)
        }
        .buttonStyle(.borderedProminent)
        .tint(selectedIndices.isEmpty ? Color(UIColor.darkGray) : .cyan)
        .disabled(selectedIndices.isEmpty)
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.top, LiquidSpacing.lg)
    }

    private var confirmButtonTitle: String {
        if selectedIndices.isEmpty {
            return "Select at least one person"
        }
        let count = selectedIndices.count
        return "Track \(count) Person\(count > 1 ? "s" : "")"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LiquidSpacing.lg) {
            dragHandle

            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Persons Detected")
                .font(LiquidTypography.title3)
                .foregroundStyle(.white)

            Text("The video does not contain detectable people,\nor the selected algorithm could not find any.")
                .font(LiquidTypography.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onDismiss?()
                dismiss()
            } label: {
                Text("Close")
                    .font(LiquidTypography.calloutMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.md + 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)
            .padding(.horizontal, LiquidSpacing.lg)
        }
        .padding(.horizontal, LiquidSpacing.xxxl)
        .background(.ultraThinMaterial)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 0)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: LiquidSpacing.cornerXLarge,
                topTrailingRadius: LiquidSpacing.cornerXLarge
            )
        )
    }

    // MARK: - Actions

    private func toggleSelection(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
