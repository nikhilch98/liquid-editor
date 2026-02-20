// TrackDebugSheet.swift
// LiquidEditor
//
// Developer sheet displaying comprehensive tracking debug information
// for a completed analysis session. Shows per-track confidence stats,
// gap analysis, ReID events, post-tracking merges, and identity matches.
//
// Accessible via EditorToolbar > tracking icon (debug build) or
// long-press on the tracking status indicator.

import SwiftUI

// MARK: - TrackDebugSheet

/// Sheet displaying tracking debug info for one analysis session.
struct TrackDebugSheet: View {

    // MARK: - Input

    let sessionId: String
    let onClose: () -> Void

    // MARK: - State

    @State private var summary: TrackingDebugSummary?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var expandedTrackId: Int?

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(Color.white.opacity(0.1))
            content
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        .frame(maxHeight: 600)
        .task {
            await loadDebugInfo()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ant.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LiquidColors.warning)
                .accessibilityHidden(true)

            Text("Track Debug Results")
                .font(LiquidTypography.headline)
                .foregroundStyle(.white)

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(white: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close debug sheet")
        }
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.vertical, LiquidSpacing.md)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let error = loadError {
            errorView(message: error)
        } else if summary == nil || summary!.tracks.isEmpty {
            emptyView
        } else {
            scrollContent
        }
    }

    private var loadingView: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Loading tracking data…")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LiquidSpacing.xxxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading tracking data")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: LiquidSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(LiquidColors.error)
            Text("Error: \(message)")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.error.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xxxl)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LiquidSpacing.xxxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading tracking data: \(message)")
    }

    private var emptyView: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Spacer()
            Image(systemName: "person.slash")
                .font(.system(size: 32))
                .foregroundStyle(LiquidColors.textSecondary)
            Text("No tracking data available")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LiquidSpacing.xxxl)
        .accessibilityLabel("No tracking data available for this session")
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: LiquidSpacing.md) {
                if let s = summary {
                    overviewCard(summary: s)
                    postTrackingMergeCard(summary: s)
                    reidStatusCard(summary: s)
                    identificationCard(summary: s)

                    ForEach(s.tracks, id: \.trackId) { track in
                        trackCard(track: track)
                    }

                    copyButton(summary: s)
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
        }
    }

    // MARK: - Overview Card

    private func overviewCard(summary: TrackingDebugSummary) -> some View {
        debugCard(color: .cyan) {
            cardHeader(
                icon: "person.2.fill",
                iconColor: .cyan,
                title: "Overview",
                badge: "\(summary.uniquePersonCount) persons"
            )

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, LiquidSpacing.xs)

            statsGrid([
                ("Unique Persons", "\(summary.uniquePersonCount)", .white),
                ("Raw Tracks", "\(summary.rawTrackCount)", .white),
                ("ReID Merges", "\(summary.reidMergeCount)", .cyan),
                ("Fragmentation ↓", "\(String(format: "%.1f", summary.fragmentationReduction))%", .green),
            ])
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overview: \(summary.uniquePersonCount) persons detected, \(summary.reidMergeCount) ReID merges, \(String(format: "%.1f", summary.fragmentationReduction))% fragmentation reduction")
    }

    // MARK: - Post-Tracking Merge Card

    private func postTrackingMergeCard(summary: TrackingDebugSummary) -> some View {
        let hasMerges = summary.postTrackingMergeCount > 0
        let cardColor: Color = hasMerges ? .teal : .gray

        return debugCard(color: cardColor) {
            cardHeader(
                icon: hasMerges ? "arrow.triangle.merge" : "arrow.branch",
                iconColor: cardColor,
                title: "Post-Tracking Merge",
                badge: summary.postTrackingMergeEnabled
                    ? (hasMerges
                        ? "\(summary.postTrackingMergeCount) MERGES"
                        : "NO MERGES")
                    : "DISABLED"
            )

            if summary.postTrackingMergeEnabled {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, LiquidSpacing.xs)

                HStack(spacing: LiquidSpacing.sm) {
                    statItem(label: "Before Merge", value: "\(summary.tracksBeforeMerge) tracks", color: .gray)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(hasMerges ? Color.teal : Color.gray)
                    statItem(label: "After Merge", value: "\(summary.tracksAfterMerge) tracks",
                             color: hasMerges ? .teal : .green)
                }

                if hasMerges {
                    statsGrid([
                        ("Merges", "\(summary.postTrackingMergeCount)", .teal),
                        ("Fragmentation ↓",
                         "\(String(format: "%.1f", summary.postTrackingFragmentationReduction))%",
                         .green),
                    ])

                    if !summary.postTrackingMergeDetails.isEmpty {
                        mergeDetailsSection(details: summary.postTrackingMergeDetails)
                    }
                }
            }
        }
    }

    private func mergeDetailsSection(details: [TrackMergeDebugDetail]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            Text("MERGE DETAILS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.gray.opacity(0.8))
                .kerning(1)
                .padding(.top, LiquidSpacing.xs)

            ForEach(details.prefix(5), id: \.fromTrackId) { detail in
                HStack(spacing: LiquidSpacing.sm) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.teal.opacity(0.7))
                    Text("Track \(detail.fromTrackId) → Track \(detail.toTrackId)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text(String(format: "%.2f", detail.similarity))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.teal)
                }
            }
        }
        .padding(LiquidSpacing.sm)
        .background(Color.teal.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous))
    }

    // MARK: - ReID Status Card

    private func reidStatusCard(summary: TrackingDebugSummary) -> some View {
        let enabled = summary.reidEnabled
        return debugCard(color: enabled ? .orange : .gray) {
            cardHeader(
                icon: "arrow.clockwise.circle.fill",
                iconColor: enabled ? .orange : .gray,
                title: "Re-Identification (ReID)",
                badge: enabled ? "ENABLED" : "DISABLED"
            )

            if enabled {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, LiquidSpacing.xs)

                statsGrid([
                    ("Raw Tracks", "\(summary.rawTrackCount)", .white),
                    ("After ReID", "\(summary.uniquePersonCount)", .orange),
                    ("Merges", "\(summary.reidMergeCount)", .orange),
                    ("Reduction",
                     "\(String(format: "%.1f", summary.fragmentationReduction))%",
                     .green),
                ])
            }
        }
    }

    // MARK: - Identification Card

    private func identificationCard(summary: TrackingDebugSummary) -> some View {
        let rate = summary.identificationRate
        let identified = summary.identifiedTrackCount
        let color: Color = rate > 50 ? .green : (rate > 0 ? .orange : .gray)

        return debugCard(color: color) {
            cardHeader(
                icon: "person.crop.circle.badge.checkmark",
                iconColor: color,
                title: "People Library",
                badge: "\(identified)/\(summary.uniquePersonCount)"
            )

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, LiquidSpacing.xs)

            statsGrid([
                ("Identified", "\(identified)", color),
                ("Unidentified", "\(summary.uniquePersonCount - identified)", .gray),
                ("Rate", "\(String(format: "%.1f", rate))%", color),
            ])
        }
    }

    // MARK: - Per-Track Card

    private func trackCard(track: TrackDebugInfo) -> some View {
        let isExpanded = expandedTrackId == track.trackId
        let stateColor = trackStateColor(track.state)

        return debugCard(color: stateColor.opacity(0.8)) {
            // Track header — tappable to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedTrackId = isExpanded ? nil : track.trackId
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                cardHeader(
                    icon: "person.fill",
                    iconColor: stateColor,
                    title: "Track \(track.trackId)",
                    badge: track.state.uppercased(),
                    chevronExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Track \(track.trackId), \(track.state). \(isExpanded ? "Tap to collapse" : "Tap to expand")")

            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, LiquidSpacing.xs)

                trackDetailContent(track: track)
            }
        }
    }

    @ViewBuilder
    private func trackDetailContent(track: TrackDebugInfo) -> some View {
        // Time range
        sectionLabel("TIME RANGE")
        statsGrid([
            ("First Frame", "\(track.firstFrameMs)ms", .white),
            ("Last Frame", "\(track.lastFrameMs)ms", .white),
            ("Total Frames", "\(track.totalFrames)", .white),
        ])

        // Confidence
        sectionLabel("CONFIDENCE")
        statsGrid([
            ("Average", String(format: "%.2f", track.avgConfidence), confidenceColor(track.avgConfidence)),
            ("Min", String(format: "%.2f", track.minConfidence), confidenceColor(track.minConfidence)),
            ("Max", String(format: "%.2f", track.maxConfidence), confidenceColor(track.maxConfidence)),
        ])

        // Confidence histogram
        confidenceHistogramView(histogram: track.confidenceHistogram)

        // Gaps
        if track.gapCount > 0 {
            sectionLabel("GAPS (\(track.gapCount))")
            statsGrid([
                ("Gap Count", "\(track.gapCount)", .orange),
                ("Total Gap", "\(track.totalGapDurationMs)ms", .orange),
                ("Longest Gap", "\(track.longestGapMs)ms", .orange),
            ])
            ForEach(track.gaps.prefix(3).indices, id: \.self) { i in
                let gap = track.gaps[i]
                gapRow(gap: gap, index: i)
            }
        }

        // Motion
        sectionLabel("MOTION")
        statsGrid([
            ("Class", track.motionClassification.rawValue.capitalized, motionClassColor(track.motionClassification)),
            ("Avg Velocity", String(format: "%.4f", track.avgVelocity), .white),
            ("Max Velocity", String(format: "%.4f", track.maxVelocity), .white),
        ])

        // Identification
        if track.isIdentified {
            sectionLabel("IDENTIFIED")
            statsGrid([
                ("Name", track.identifiedPersonName ?? "–", .green),
                ("Confidence",
                 track.identificationConfidence.map { String(format: "%.1f%%", $0 * 100) } ?? "–",
                 .green),
            ])
        }
    }

    private func confidenceHistogramView(histogram: [Int]) -> some View {
        let maxCount = histogram.max() ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            Text("CONFIDENCE DISTRIBUTION")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.gray.opacity(0.8))
                .kerning(1)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<histogram.count, id: \.self) { i in
                    let fraction = maxCount > 0 ? Double(histogram[i]) / Double(maxCount) : 0
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(confidenceBucketColor(bucket: i))
                            .frame(height: max(4, 32 * fraction))
                        Text("\(i)0")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.gray.opacity(0.6))
                    }
                }
            }
            .frame(height: 44)
        }
        .padding(.top, LiquidSpacing.xs)
        .accessibilityLabel("Confidence histogram with 10 buckets from 0% to 100%")
    }

    private func gapRow(gap: TrackGap, index: Int) -> some View {
        HStack(spacing: LiquidSpacing.sm) {
            Text("Gap \(index + 1)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange)
            Spacer()
            Text("\(gap.startMs)ms → \(gap.endMs)ms")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Text(gap.likelyReason.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .accessibilityLabel("Gap \(index + 1): \(gap.startMs) to \(gap.endMs) milliseconds, reason: \(gap.likelyReason.rawValue)")
    }

    // MARK: - Copy Button

    private func copyButton(summary: TrackingDebugSummary) -> some View {
        Button {
            let text = buildDebugText(summary: summary)
            UIPasteboard.general.string = text
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: LiquidSpacing.sm) {
                Image(systemName: "doc.on.doc")
                    .font(LiquidTypography.subheadline)
                Text("Copy Debug Info")
                    .font(LiquidTypography.subheadlineSemibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidSpacing.md)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy debug information to clipboard")
        .padding(.top, LiquidSpacing.xs)
    }

    // MARK: - Shared Components

    private func debugCard<Content: View>(
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            content()
        }
        .padding(LiquidSpacing.md)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    private func cardHeader(
        icon: String,
        iconColor: Color,
        title: String,
        badge: String,
        chevronExpanded: Bool? = nil
    ) -> some View {
        HStack(spacing: LiquidSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            Text(title)
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(.white.opacity(0.9))

            Spacer()

            Text(badge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(iconColor)
                .padding(.horizontal, LiquidSpacing.sm)
                .padding(.vertical, LiquidSpacing.xxs)
                .background(iconColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .kerning(0.5)

            if let expanded = chevronExpanded {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.gray.opacity(0.8))
            .kerning(1)
            .padding(.top, LiquidSpacing.xs)
    }

    private func statsGrid(_ items: [(label: String, value: String, color: Color)]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: LiquidSpacing.sm), count: min(items.count, 3))
        return LazyVGrid(columns: columns, spacing: LiquidSpacing.sm) {
            ForEach(items.indices, id: \.self) { i in
                statItem(label: items[i].label, value: items[i].value, color: items[i].color)
            }
        }
    }

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.gray.opacity(0.7))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LiquidSpacing.sm)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Colors

    private func confidenceColor(_ confidence: Float) -> Color {
        switch confidence {
        case 0.8...: return .green
        case 0.5..<0.8: return .orange
        default: return .red
        }
    }

    private func confidenceBucketColor(bucket: Int) -> Color {
        switch bucket {
        case 8, 9: return .green
        case 5, 6, 7: return .orange
        default: return .red
        }
    }

    private func motionClassColor(_ motion: MotionClass) -> Color {
        switch motion {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func trackStateColor(_ state: String) -> Color {
        switch state {
        case "confirmed": return .cyan
        case "lost": return .orange
        case "archived": return .gray
        default: return .purple
        }
    }

    // MARK: - Data Loading

    private func loadDebugInfo() async {
        isLoading = true
        loadError = nil

        let trackingService = ServiceContainer.shared.trackingService
        if let result = await trackingService.getDebugSummary(for: sessionId) {
            summary = result
        } else {
            loadError = "No tracking data found for session \(sessionId)"
        }

        isLoading = false
    }

    // MARK: - Debug Text Export

    private func buildDebugText(summary: TrackingDebugSummary) -> String {
        var lines: [String] = [
            "=== LiquidEditor Track Debug ===",
            "Session: \(sessionId)",
            "",
            "OVERVIEW",
            "  Unique Persons: \(summary.uniquePersonCount)",
            "  Raw Tracks: \(summary.rawTrackCount)",
            "  ReID Merges: \(summary.reidMergeCount)",
            "  Fragmentation Reduction: \(String(format: "%.1f", summary.fragmentationReduction))%",
            "",
            "POST-TRACKING MERGE",
            "  Enabled: \(summary.postTrackingMergeEnabled)",
            "  Tracks Before: \(summary.tracksBeforeMerge)",
            "  Tracks After: \(summary.tracksAfterMerge)",
            "  Merges: \(summary.postTrackingMergeCount)",
            "",
        ]

        for track in summary.tracks {
            lines.append("TRACK \(track.trackId) [\(track.state.uppercased())]")
            lines.append("  Frames: \(track.firstFrameMs)ms – \(track.lastFrameMs)ms (\(track.totalFrames) frames)")
            lines.append("  Confidence: avg=\(String(format: "%.2f", track.avgConfidence)) min=\(String(format: "%.2f", track.minConfidence)) max=\(String(format: "%.2f", track.maxConfidence))")
            lines.append("  Gaps: \(track.gapCount) (total \(track.totalGapDurationMs)ms)")
            lines.append("  Motion: \(track.motionClassification.rawValue) (avg vel=\(String(format: "%.4f", track.avgVelocity)))")
            if track.isIdentified {
                lines.append("  Identity: \(track.identifiedPersonName ?? "unknown") (conf=\(track.identificationConfidence.map { String(format: "%.1f%%", $0 * 100) } ?? "–"))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Preview

#Preview {
    Color.black
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            TrackDebugSheet(sessionId: "preview-session") {}
                .padding()
        }
        .preferredColorScheme(.dark)
}
