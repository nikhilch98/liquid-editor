// ExportDebugSheet.swift
// LiquidEditor
//
// Debug interface showing side-by-side preview vs export frame comparison,
// transform debug info, codec details, and timeline clip data.
// iOS 26 SwiftUI with Liquid Glass styling.

import SwiftUI

// MARK: - ExportDebugMode

/// Display mode for the frame comparison.
enum ExportDebugMode: String, CaseIterable, Sendable, Identifiable {
    case sideBySide
    case overlay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sideBySide: return "Side by Side"
        case .overlay: return "Overlay"
        }
    }
}

// MARK: - ExportDebugInfo

/// Debug information about the export pipeline.
///
/// Contains transform data, dimensions, codec info, and timeline clip details
/// for diagnosing preview-vs-export mismatches.
struct ExportDebugInfo: Sendable {

    // MARK: - Dimensions

    /// Preview render width.
    let previewWidth: Double?

    /// Preview render height.
    let previewHeight: Double?

    /// Export output width.
    let exportWidth: Int?

    /// Export output height.
    let exportHeight: Int?

    /// Source media width.
    let sourceWidth: Double?

    /// Source media height.
    let sourceHeight: Double?

    // MARK: - Transform

    /// Scale factor applied during export.
    let scale: Double?

    /// Horizontal translation.
    let tx: Double?

    /// Vertical translation.
    let ty: Double?

    /// Rotation angle in radians.
    let rotation: Double?

    // MARK: - Codec

    /// Video codec name.
    let codec: String?

    /// Video bitrate in Mbps.
    let bitrateMbps: Double?

    /// Frames per second.
    let fps: Int?

    // MARK: - Timeline Clips

    /// Number of clips on the timeline.
    let clipCount: Int

    /// Per-clip debug data.
    let clips: [ClipDebugInfo]

    // MARK: - Timing

    /// Total export elapsed time in seconds.
    let elapsedSeconds: Double?

    /// Total frames rendered.
    let framesRendered: Int?

    init(
        previewWidth: Double? = nil,
        previewHeight: Double? = nil,
        exportWidth: Int? = nil,
        exportHeight: Int? = nil,
        sourceWidth: Double? = nil,
        sourceHeight: Double? = nil,
        scale: Double? = nil,
        tx: Double? = nil,
        ty: Double? = nil,
        rotation: Double? = nil,
        codec: String? = nil,
        bitrateMbps: Double? = nil,
        fps: Int? = nil,
        clipCount: Int = 0,
        clips: [ClipDebugInfo] = [],
        elapsedSeconds: Double? = nil,
        framesRendered: Int? = nil
    ) {
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.exportWidth = exportWidth
        self.exportHeight = exportHeight
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.scale = scale
        self.tx = tx
        self.ty = ty
        self.rotation = rotation
        self.codec = codec
        self.bitrateMbps = bitrateMbps
        self.fps = fps
        self.clipCount = clipCount
        self.clips = clips
        self.elapsedSeconds = elapsedSeconds
        self.framesRendered = framesRendered
    }

    /// Create from a raw dictionary (e.g., from platform channel).
    static func fromMap(_ map: [String: Any]) -> ExportDebugInfo {
        let clipList = map["clips"] as? [[String: Any]] ?? []
        let clips = clipList.enumerated().map { index, clip in
            ClipDebugInfo(
                index: index,
                orderIndex: clip["orderIndex"] as? Int ?? index,
                sourceInMs: clip["sourceIn"] as? Int ?? 0,
                sourceOutMs: clip["sourceOut"] as? Int ?? 0
            )
        }

        return ExportDebugInfo(
            previewWidth: map["previewWidth"] as? Double,
            previewHeight: map["previewHeight"] as? Double,
            exportWidth: map["exportWidth"] as? Int,
            exportHeight: map["exportHeight"] as? Int,
            sourceWidth: map["sourceWidth"] as? Double,
            sourceHeight: map["sourceHeight"] as? Double,
            scale: map["scale"] as? Double,
            tx: map["tx"] as? Double,
            ty: map["ty"] as? Double,
            rotation: map["rotation"] as? Double,
            codec: map["codec"] as? String,
            bitrateMbps: map["bitrateMbps"] as? Double,
            fps: map["fps"] as? Int,
            clipCount: map["clipCount"] as? Int ?? clipList.count,
            clips: clips,
            elapsedSeconds: map["elapsedSeconds"] as? Double,
            framesRendered: map["framesRendered"] as? Int
        )
    }
}

// MARK: - ClipDebugInfo

/// Debug information for a single timeline clip.
struct ClipDebugInfo: Identifiable, Sendable {
    let id = UUID()
    let index: Int
    let orderIndex: Int
    let sourceInMs: Int
    let sourceOutMs: Int
}

// MARK: - ExportDebugSheet

/// Debug sheet for comparing preview frames with export frames.
///
/// Provides side-by-side and overlay comparison modes, along with
/// detailed transform and codec debug information.
struct ExportDebugSheet: View {

    /// Preview frame image data.
    let previewFrame: Data

    /// Export frame image data.
    let exportFrame: Data

    /// Debug information dictionary.
    let debugInfo: ExportDebugInfo

    @State private var mode: ExportDebugMode = .sideBySide
    @State private var overlayOpacity: Double = 0.5
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode toggle
                modeToggle

                // Comparison view
                Group {
                    switch mode {
                    case .sideBySide:
                        sideBySideView
                    case .overlay:
                        overlayView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Debug info panel
                debugInfoPanel
            }
            .background(Color.black)
            .navigationTitle("Export Debug Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: LiquidSpacing.sm) {
            Picker("Mode", selection: $mode) {
                ForEach(ExportDebugMode.allCases) { debugMode in
                    Text(debugMode.label).tag(debugMode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .accessibilityLabel("Comparison mode")

            if mode == .overlay {
                HStack(spacing: LiquidSpacing.xs) {
                    Text("Opacity:")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: $overlayOpacity, in: 0...1)
                        .tint(LiquidColors.primary)
                        .accessibilityLabel("Export overlay opacity")
                        .accessibilityValue("\(Int(overlayOpacity * 100)) percent")
                }
            }

            Spacer()
        }
        .padding(.horizontal, LiquidSpacing.xl)
        .padding(.vertical, LiquidSpacing.sm)
    }

    // MARK: - Side by Side View

    private var sideBySideView: some View {
        HStack(spacing: LiquidSpacing.md) {
            // Preview frame
            VStack(spacing: LiquidSpacing.sm) {
                Text("PREVIEW")
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(LiquidColors.success)
                    .padding(.horizontal, LiquidSpacing.md)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(Color.green.opacity(0.3), in: RoundedRectangle(cornerRadius: LiquidSpacing.xs))

                // Subtle green tint on the preview frame so it is visually
                // distinguishable from the export frame at a glance.
                // Near-white with a green bias: rgb(0.9, 1.0, 0.9) ≈ 10 % green tint.
                frameImage(
                    data: previewFrame,
                    borderColor: .green,
                    tintColor: Color(red: 0.9, green: 1.0, blue: 0.9)
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview frame")

            // Export frame
            VStack(spacing: LiquidSpacing.sm) {
                Text("EXPORT")
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, LiquidSpacing.md)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(Color.orange.opacity(0.3), in: RoundedRectangle(cornerRadius: LiquidSpacing.xs))

                // Subtle orange tint on the export frame.
                // Near-white with an orange bias: rgb(1.0, 0.93, 0.9) ≈ 10 % orange tint.
                frameImage(
                    data: exportFrame,
                    borderColor: .orange,
                    tintColor: Color(red: 1.0, green: 0.93, blue: 0.9)
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Export frame")
        }
        .padding(LiquidSpacing.lg)
    }

    // MARK: - Overlay View

    private var overlayView: some View {
        VStack(spacing: LiquidSpacing.sm) {
            // Legend
            HStack(spacing: LiquidSpacing.lg) {
                HStack(spacing: LiquidSpacing.xs) {
                    Circle().fill(.green).frame(width: LiquidSpacing.md, height: LiquidSpacing.md)
                    Text("Preview").font(LiquidTypography.caption).foregroundStyle(LiquidColors.success)
                }
                HStack(spacing: LiquidSpacing.xs) {
                    Circle().fill(.orange).frame(width: LiquidSpacing.md, height: LiquidSpacing.md)
                    Text("Export").font(LiquidTypography.caption).foregroundStyle(.orange)
                }
            }

            // Overlaid frames
            ZStack {
                if let previewImage = imageFromData(previewFrame) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .colorMultiply(.green)
                }

                if let exportImage = imageFromData(exportFrame) {
                    Image(uiImage: exportImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .colorMultiply(.orange)
                        .opacity(overlayOpacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(LiquidSpacing.lg)
        }
    }

    // MARK: - Frame Image

    /// Renders a frame image with a coloured border and an optional subtle colour tint.
    ///
    /// The tint is applied via `.colorMultiply` using a near-white colour whose hue
    /// matches the intended tint colour.  The effective blend is equivalent to the
    /// Flutter `BlendMode.modulate` at 10 % opacity, i.e. a barely-visible hue cast.
    ///
    /// For a **green** tint pass `Color(red: 0.9, green: 1.0, blue: 0.9)`.
    /// For an **orange** tint pass `Color(red: 1.0, green: 0.93, blue: 0.9)`.
    ///
    /// - Parameters:
    ///   - data: Raw PNG/JPEG image data.
    ///   - borderColor: Stroke colour used for the rounded-rectangle border.
    ///   - tintColor: Near-white colour used as the `.colorMultiply` argument.
    ///     Pass `nil` (default) to skip tinting.
    @ViewBuilder
    private func frameImage(data: Data, borderColor: Color, tintColor: Color? = nil) -> some View {
        if let uiImage = imageFromData(data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                // colorMultiply multiplies each pixel's RGB by the tint colour's RGB.
                // Using a near-white colour (e.g. 0.9,1.0,0.9 for green) produces a
                // subtle hue cast that matches the Flutter BlendMode.modulate at 10 %.
                .colorMultiply(tintColor ?? .white)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .stroke(borderColor.opacity(0.5), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Text("No image")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Debug Info Panel

    private var debugInfoPanel: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.md) {
            Text("Transform Debug Info")
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(.yellow)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 16) {
                // Dimensions column
                infoColumn(title: "Dimensions", items: [
                    "Preview: \(formatOptional(debugInfo.previewWidth)) x \(formatOptional(debugInfo.previewHeight))",
                    "Export: \(formatOptionalInt(debugInfo.exportWidth)) x \(formatOptionalInt(debugInfo.exportHeight))",
                    "Source: \(formatOptional(debugInfo.sourceWidth)) x \(formatOptional(debugInfo.sourceHeight))",
                ])

                // Transform column
                infoColumn(title: "Transform", items: [
                    "Scale: \(formatOptional(debugInfo.scale))",
                    "Tx: \(formatOptional(debugInfo.tx))",
                    "Ty: \(formatOptional(debugInfo.ty))",
                    "Rotation: \(formatOptional(debugInfo.rotation))",
                ])
            }

            // Codec info
            if debugInfo.codec != nil || debugInfo.bitrateMbps != nil || debugInfo.fps != nil {
                infoColumn(title: "Codec", items: [
                    debugInfo.codec.map { "Codec: \($0)" },
                    debugInfo.bitrateMbps.map { "Bitrate: \(String(format: "%.1f", $0)) Mbps" },
                    debugInfo.fps.map { "FPS: \($0)" },
                    debugInfo.framesRendered.map { "Frames: \($0)" },
                    debugInfo.elapsedSeconds.map { "Elapsed: \(String(format: "%.1f", $0))s" },
                ].compactMap { $0 })
            }

            // Timeline clips
            if debugInfo.clipCount > 0 {
                Text("Timeline Clips (\(debugInfo.clipCount))")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.cyan)

                ForEach(debugInfo.clips) { clip in
                    Text("[\(clip.index)] order=\(clip.orderIndex), src=\(clip.sourceInMs)ms-\(clip.sourceOutMs)ms")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(LiquidSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    // MARK: - Info Column

    private func infoColumn(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            Text(title)
                .font(LiquidTypography.caption2Semibold)
                .foregroundStyle(.white.opacity(0.7))

            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func imageFromData(_ data: Data) -> UIImage? {
        UIImage(data: data)
    }

    private func formatOptional(_ value: Double?) -> String {
        guard let value else { return "null" }
        return String(format: "%.4f", value)
    }

    private func formatOptionalInt(_ value: Int?) -> String {
        guard let value else { return "null" }
        return "\(value)"
    }
}

// MARK: - Preview

#Preview {
    // Create simple 1x1 pixel PNG data for preview
    let pixelData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
        0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
    ])

    ExportDebugSheet(
        previewFrame: pixelData,
        exportFrame: pixelData,
        debugInfo: ExportDebugInfo(
            previewWidth: 375.0,
            previewHeight: 667.0,
            exportWidth: 1920,
            exportHeight: 1080,
            sourceWidth: 1920.0,
            sourceHeight: 1080.0,
            scale: 0.1953,
            tx: 0.0,
            ty: 0.0,
            rotation: 0.0,
            codec: "H.264 (AVC)",
            bitrateMbps: 20.0,
            fps: 30,
            clipCount: 2,
            clips: [
                ClipDebugInfo(index: 0, orderIndex: 0, sourceInMs: 0, sourceOutMs: 5000),
                ClipDebugInfo(index: 1, orderIndex: 1, sourceInMs: 5000, sourceOutMs: 12000),
            ],
            elapsedSeconds: 4.5,
            framesRendered: 360
        )
    )
}
