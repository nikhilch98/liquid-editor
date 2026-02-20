// TrackManagementSheet.swift
// LiquidEditor
//
// Track management sheet view.
// Pure iOS 26 SwiftUI with native styling.
//
// Matches Flutter TrackManagementPanel layout:
// - Header with "Tracks" title, track count badge, X close button
// - Track rows: drag handle, color indicator, name, "Type . N clips" subtitle,
//   mute, lock, visibility, delete (non-main only)
// - Overlay track limit progress bar (N/8)
// - "Add Track" button opens action sheet with 4 options

import SwiftUI

/// Lightweight track representation for the track management UI.
struct TrackInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var trackType: TrackType
    var isMuted: Bool
    var isLocked: Bool
    var isVisible: Bool
    var isOverlay: Bool
    var clipCount: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        trackType: TrackType = .overlayVideo,
        isMuted: Bool = false,
        isLocked: Bool = false,
        isVisible: Bool = true,
        isOverlay: Bool = false,
        clipCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.trackType = trackType
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.isVisible = isVisible
        self.isOverlay = isOverlay
        self.clipCount = clipCount
    }

    /// Color for this track type (derived from TrackType).
    var trackColor: Color {
        Color(argb32: trackType.defaultColorARGB32)
    }
}

// MARK: - Color Extension for ARGB32

private extension Color {
    init(argb32: Int) {
        let alpha = Double((argb32 >> 24) & 0xFF) / 255.0
        let red   = Double((argb32 >> 16) & 0xFF) / 255.0
        let green = Double((argb32 >>  8) & 0xFF) / 255.0
        let blue  = Double( argb32        & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct TrackManagementSheet: View {

    @State private var tracks: [TrackInfo]
    @State private var selectedTrackId: String?
    @State private var showAddTrackSheet = false
    @State private var trackToDelete: TrackInfo?

    @Environment(\.dismiss) private var dismiss

    let maxOverlayTracks: Int
    let onApply: ([TrackInfo]) -> Void

    init(
        tracks: [TrackInfo] = [],
        maxOverlayTracks: Int = 8,
        onApply: @escaping ([TrackInfo]) -> Void
    ) {
        _tracks = State(initialValue: tracks)
        self.maxOverlayTracks = maxOverlayTracks
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header row
            headerRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            // Track list
            if tracks.isEmpty {
                emptyTrackList
            } else {
                trackList
            }

            Divider()

            // Overlay track limit progress bar
            if overlayTrackCount > 0 {
                overlayLimitBar
            }

            // Add Track button
            addTrackButton
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Add Track", isPresented: $showAddTrackSheet, titleVisibility: .visible) {
            Button("Video") { addTrack(type: .overlayVideo, label: "Video") }
            Button("Audio") { addTrack(type: .audio, label: "Audio") }
            Button("Text") { addTrack(type: .text, label: "Text") }
            Button("Sticker / Overlay") { addTrack(type: .sticker, label: "Sticker") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select the type of track to add")
        }
        .alert(
            "Delete Track?",
            isPresented: Binding(
                get: { trackToDelete != nil },
                set: { if !$0 { trackToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                trackToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let track = trackToDelete {
                    confirmDeleteTrack(track)
                }
                trackToDelete = nil
            }
        } message: {
            if let track = trackToDelete {
                Text("Are you sure you want to delete \"\(track.name)\"? This action cannot be undone.")
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Tracks")
                .font(LiquidTypography.headline)

            // Track count badge
            Text("\(tracks.count) tracks")
                .font(LiquidTypography.captionMedium)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs)
                .background(Color.indigo.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                .foregroundStyle(.indigo)
                .accessibilityLabel("\(tracks.count) tracks total")

            Spacer()

            Button {
                onApply(tracks)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Empty State

    private var emptyTrackList: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "rectangle.stack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No tracks yet")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Track List

    private var trackList: some View {
        List {
            ForEach($tracks) { $track in
                trackRow(track: $track)
                    .listRowBackground(
                        selectedTrackId == track.id
                            ? track.trackColor.opacity(0.12)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTrackId = track.id
                        }
                    }
            }
            .onMove(perform: moveTracks)
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Track Row

    private func trackRow(track: Binding<TrackInfo>) -> some View {
        let isMain = !track.wrappedValue.isOverlay

        return HStack(spacing: LiquidSpacing.sm) {
            // Drag handle (non-main tracks only)
            if !isMain {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            // Color indicator bar (4pt wide)
            RoundedRectangle(cornerRadius: 2)
                .fill(track.wrappedValue.trackColor)
                .frame(width: 4, height: 32)

            // Track info
            VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                Text(track.wrappedValue.name)
                    .font(LiquidTypography.subheadlineMedium)
                    .lineLimit(1)

                Text("\(track.wrappedValue.trackType.displayName) \u{00B7} \(track.wrappedValue.clipCount) clips")
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Control buttons
            HStack(spacing: LiquidSpacing.xs) {
                // Mute
                trackControlButton(
                    icon: track.wrappedValue.isMuted
                        ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isActive: track.wrappedValue.isMuted,
                    activeColor: .red
                ) {
                    track.wrappedValue.isMuted.toggle()
                }

                // Lock
                trackControlButton(
                    icon: track.wrappedValue.isLocked
                        ? "lock.fill" : "lock.open",
                    isActive: track.wrappedValue.isLocked,
                    activeColor: .orange
                ) {
                    track.wrappedValue.isLocked.toggle()
                }

                // Visibility
                trackControlButton(
                    icon: track.wrappedValue.isVisible
                        ? "eye.fill" : "eye.slash.fill",
                    isActive: !track.wrappedValue.isVisible,
                    activeColor: .gray
                ) {
                    track.wrappedValue.isVisible.toggle()
                }

                // Delete (non-main only)
                if !isMain {
                    trackControlButton(
                        icon: "trash",
                        isActive: false,
                        activeColor: .red
                    ) {
                        trackToDelete = track.wrappedValue
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func trackControlButton(
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(LiquidTypography.caption)
                .foregroundStyle(isActive ? activeColor : .primary.opacity(0.45))
                .frame(width: LiquidSpacing.xxxl - 2, height: LiquidSpacing.xxxl - 2)
                .background(
                    isActive
                        ? activeColor.opacity(0.15)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.xs + 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overlay Limit Bar

    private var overlayLimitBar: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 3)

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(canAddOverlayTrack ? Color.indigo : Color.orange)
                        .frame(
                            width: geometry.size.width * overlayProgress,
                            height: 3
                        )
                }
            }
            .frame(height: 3)

            Text("\(overlayTrackCount) / \(maxOverlayTracks) overlay")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Add Track Button

    private var addTrackButton: some View {
        Button {
            showAddTrackSheet = true
        } label: {
            Text("Add Track")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAddOverlayTrack)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func moveTracks(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteTrack(_ track: TrackInfo) {
        guard track.isOverlay else { return }
        tracks.removeAll { $0.id == track.id }
    }

    private func confirmDeleteTrack(_ track: TrackInfo) {
        deleteTrack(track)
    }

    private func addTrack(type: TrackType, label: String) {
        guard canAddOverlayTrack else { return }
        let trackNumber = tracks.count + 1
        let newTrack = TrackInfo(
            name: "\(label) \(trackNumber)",
            trackType: type,
            isOverlay: true
        )
        tracks.append(newTrack)
    }

    // MARK: - Computed

    private var overlayTrackCount: Int {
        tracks.filter(\.isOverlay).count
    }

    private var canAddOverlayTrack: Bool {
        overlayTrackCount < maxOverlayTracks
    }

    private var overlayProgress: Double {
        guard maxOverlayTracks > 0 else { return 0 }
        return Double(overlayTrackCount) / Double(maxOverlayTracks)
    }
}

#Preview {
    TrackManagementSheet(
        tracks: [
            TrackInfo(name: "Video", trackType: .mainVideo, isOverlay: false, clipCount: 3),
            TrackInfo(name: "Text 1", trackType: .text, isOverlay: true, clipCount: 2),
            TrackInfo(name: "Stickers", trackType: .sticker, isOverlay: true, clipCount: 1),
        ]
    ) { _ in }
}
