// InspectorSectionViews.swift
// LiquidEditor
//
// IM9-2 .. IM9-6: Skeletal section views for the InspectorPanel.
//
// Each view is a thin wrapper used by the InspectorPanel section
// renderer to populate a section by `InspectorSectionID`. The actual
// data wiring (binding to selected clip's ColorGrade, EffectChain,
// Keyframe etc.) is performed by section providers in the editor view
// model when these are dropped into the panel.
//
// All views are stateless — selection-state owners pass the values in.

import SwiftUI

// MARK: - InspectorClipHeader (IM9-2)

/// Compact header row shown at the top of the inspector for any
/// clip selection: name, duration timecode, badge chips.
struct InspectorClipHeader: View {
    let name: String
    let duration: String
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.Text.primary)
                    .lineLimit(1)
                Spacer()
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.Text.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(LiquidColors.Canvas.elev)
                        )
                }
            }
            Text(duration)
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.tertiary)
        }
    }
}

// MARK: - InspectorTransformSection (IM9-3)

/// Position / scale / rotation row group. Three numeric input rows
/// bound to the underlying OverlayTransform.
struct InspectorTransformSection: View {
    @Binding var positionX: Double
    @Binding var positionY: Double
    @Binding var scale: Double
    @Binding var rotationDegrees: Double

    var body: some View {
        VStack(spacing: 4) {
            row(label: "X", value: $positionX, range: 0...1, format: "%.2f")
            row(label: "Y", value: $positionY, range: 0...1, format: "%.2f")
            row(label: "Scale", value: $scale, range: 0.1...4, format: "%.2fx")
            row(label: "Rotation", value: $rotationDegrees, range: -180...180, format: "%.0f\u{00B0}")
        }
    }

    private func row(label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(LiquidColors.Text.tertiary)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: range)
                .tint(LiquidColors.Accent.amber)
            Text(String(format: format, value.wrappedValue))
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - InspectorSpeedSection (IM9-4)

/// Speed multiplier with preset chips + custom slider + preserve-pitch.
struct InspectorSpeedSection: View {
    @Binding var rate: Double
    @Binding var preservePitch: Bool

    private let presets: [Double] = [0.25, 0.5, 1.0, 2.0]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { p in
                    Button { rate = p } label: {
                        Text(p == 1.0 ? "1x" : String(format: "%.2gx", p))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(rate == p ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(rate == p ? LiquidColors.Accent.amberGlow : LiquidColors.Canvas.elev)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(String(format: "%.2gx", rate))
                    .font(.caption.monospaced())
                    .foregroundStyle(LiquidColors.Text.primary)
            }
            Slider(value: $rate, in: 0.1...10).tint(LiquidColors.Accent.amber)
            Toggle("Preserve pitch", isOn: $preservePitch)
                .font(.caption)
                .toggleStyle(.switch)
                .tint(LiquidColors.Accent.amber)
        }
    }
}

// MARK: - InspectorVolumeSection (IM9-5)

/// dB slider + fade-in/out compact controls.
struct InspectorVolumeSection: View {
    @Binding var volumeDB: Double
    @Binding var fadeInMs: Double
    @Binding var fadeOutMs: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Level").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Spacer()
                Text(String(format: "%+.1f dB", volumeDB))
                    .font(.caption.monospaced())
                    .foregroundStyle(LiquidColors.Text.primary)
            }
            Slider(value: $volumeDB, in: -60...12).tint(LiquidColors.Accent.amber)
            HStack(spacing: 6) {
                Text("Fade in").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Slider(value: $fadeInMs, in: 0...3000).tint(LiquidColors.Accent.amber)
                Text("\(Int(fadeInMs)) ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("Fade out").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Slider(value: $fadeOutMs, in: 0...3000).tint(LiquidColors.Accent.amber)
                Text("\(Int(fadeOutMs)) ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

// MARK: - InspectorOpacitySection (IM9-6)

/// Single-slider opacity (0..1) with percentage readout.
struct InspectorOpacitySection: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $opacity, in: 0...1).tint(LiquidColors.Accent.amber)
            Text("\(Int(opacity * 100))%")
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.primary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - InspectorTextSection (IM9-7)

/// Text-clip content + style summary. Tapping `Edit\u2026` opens the
/// full Text Editor sheet (C5-1).
struct InspectorTextSection: View {
    @Binding var text: String
    @Binding var fontPreviewName: String
    let onOpenEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Text", text: $text)
                .font(.callout)
                .padding(6)
                .background(LiquidColors.Canvas.elev, in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Text(fontPreviewName)
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
                Spacer()
                Button("Edit style\u2026", action: onOpenEditor)
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Accent.amber)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - InspectorCaptionSection (IM9-8)

/// Caption-clip style + language picker.
struct InspectorCaptionSection: View {
    @Binding var styleName: String
    @Binding var languageCode: String

    private let styles = ["Word pop", "Line", "Bar", "Minimal"]
    private let languages = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "ja-JP"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Style", selection: $styleName) {
                ForEach(styles, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Language", selection: $languageCode) {
                ForEach(languages, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - InspectorColorGradeSection (IM9-9)

/// Compact summary of the active color grade with shortcuts to the
/// full panel (C5-6 wheels / C5-7 curves / C5-8 HSL).
struct InspectorColorGradeSection: View {
    let exposureValue: Double
    let saturationValue: Double
    let lutName: String?
    let onOpenWheels: () -> Void
    let onOpenCurves: () -> Void
    let onOpenHSL: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "Exp %+.1f", exposureValue))
                Text(String(format: "Sat %d%%", Int(saturationValue * 100)))
                if let lut = lutName {
                    Text("LUT: \(lut)")
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(LiquidColors.Text.secondary)
            HStack(spacing: 8) {
                Button("Wheels", action: onOpenWheels)
                Button("Curves", action: onOpenCurves)
                Button("HSL", action: onOpenHSL)
            }
            .font(.caption)
            .foregroundStyle(LiquidColors.Accent.amber)
            .buttonStyle(.plain)
        }
    }
}

// MARK: - InspectorAnimationSection (IM9-10)

/// Keyframe-count summary + add/edit-keyframes shortcut.
struct InspectorAnimationSection: View {
    let keyframeCount: Int
    let onAddKeyframe: () -> Void
    let onOpenLane: () -> Void

    var body: some View {
        HStack {
            Text("\(keyframeCount) keyframe\(keyframeCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(LiquidColors.Text.secondary)
            Spacer()
            Button("+ Key", action: onAddKeyframe)
            Button("Lane\u2026", action: onOpenLane)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(LiquidColors.Accent.amber)
        .buttonStyle(.plain)
    }
}

// MARK: - InspectorProjectMetaSection (IM9-11)

/// Read-only project-level info shown when no clip is selected.
struct InspectorProjectMetaSection: View {
    let resolution: String
    let frameRate: Int
    let durationDisplay: String
    let clipCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Resolution", value: resolution)
            row("Frame rate", value: "\(frameRate) fps")
            row("Duration", value: durationDisplay)
            row("Clips", value: "\(clipCount)")
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(LiquidColors.Text.tertiary)
            Spacer()
            Text(value).foregroundStyle(LiquidColors.Text.primary).font(.caption.monospaced())
        }
        .font(.caption)
    }
}

// MARK: - InspectorPlayheadSection (IM9-12)

/// Playhead timecode + snap toggle.
struct InspectorPlayheadSection: View {
    let timecode: String
    @Binding var snapEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Playhead").foregroundStyle(LiquidColors.Text.tertiary).font(.caption)
                Spacer()
                Text(timecode).font(.caption.monospaced()).foregroundStyle(LiquidColors.Text.primary)
            }
            Toggle("Snap to playhead", isOn: $snapEnabled)
                .font(.caption)
                .toggleStyle(.switch)
                .tint(LiquidColors.Accent.amber)
        }
    }
}

// MARK: - InspectorClipPropertiesSection (IM9-14)

/// Read-only metadata grid (codec, resolution, fps, duration, path).
struct InspectorClipPropertiesSection: View {
    let codec: String
    let resolution: String
    let frameRate: String
    let colorSpace: String
    let duration: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("Codec", codec)
            row("Resolution", resolution)
            row("Frame rate", frameRate)
            row("Color space", colorSpace)
            row("Duration", duration)
            row("Path", path)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(LiquidColors.Text.tertiary).font(.caption)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - InspectorProxySection (IM9-15)

/// Proxy override segmented + status line.
struct InspectorProxySection: View {
    enum ProxyMode: String, CaseIterable, Identifiable {
        case followProject = "Follow"
        case alwaysOn = "On"
        case alwaysOff = "Off"
        case regenerate = "Regenerate"
        var id: String { rawValue }
    }

    @Binding var mode: ProxyMode
    let statusLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: $mode) {
                ForEach(ProxyMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(LiquidColors.Text.tertiary)
        }
    }
}

// MARK: - InspectorBlendModeSection (IM9-16)

/// 7-option blend-mode picker (overlay-track clips only).
struct InspectorBlendModeSection: View {
    @Binding var blendModeName: String
    private let modes = ["Normal", "Multiply", "Screen", "Overlay", "Soft Light", "Add", "Subtract"]

    var body: some View {
        Picker("", selection: $blendModeName) {
            ForEach(modes, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .font(.caption)
    }
}

// MARK: - InspectorFlipRotateCropSection (IM9-17)

/// Flip horizontal / vertical, quick-rotate seg, and crop entry.
struct InspectorFlipRotateCropSection: View {
    @Binding var flipH: Bool
    @Binding var flipV: Bool
    @Binding var rotateQuarters: Int
    let onOpenCropTool: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Toggle("Flip H", isOn: $flipH).font(.caption2)
                Toggle("Flip V", isOn: $flipV).font(.caption2)
            }
            .toggleStyle(.button)
            .tint(LiquidColors.Accent.amber)
            Picker("Rotate", selection: $rotateQuarters) {
                Text("0\u{00B0}").tag(0)
                Text("90\u{00B0}").tag(1)
                Text("180\u{00B0}").tag(2)
                Text("270\u{00B0}").tag(3)
            }
            .pickerStyle(.segmented)
            Button("Crop\u2026", action: onOpenCropTool)
                .font(.caption)
                .foregroundStyle(LiquidColors.Accent.amber)
                .buttonStyle(.plain)
        }
    }
}

// MARK: - InspectorAudioPanSection (IM9-18)

/// Stereo pan slider −1.0 … +1.0 with center detent label.
struct InspectorAudioPanSection: View {
    @Binding var pan: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("L").font(.caption2).foregroundStyle(LiquidColors.Text.tertiary)
                Slider(value: $pan, in: -1...1).tint(LiquidColors.Accent.amber)
                Text("R").font(.caption2).foregroundStyle(LiquidColors.Text.tertiary)
            }
            Text(panLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var panLabel: String {
        if abs(pan) < 0.01 { return "Center" }
        let percent = Int(abs(pan) * 100)
        return pan < 0 ? "L \(percent)%" : "R \(percent)%"
    }
}

// MARK: - InspectorAudioEffectsStackSection (IM9-19)

/// Compact list of applied audio effects with bypass toggles. Reorder
/// is delegated to the parent (drag handle wrapper).
struct InspectorAudioEffectsStackSection: View {
    let effectNames: [String]
    let onTap: (Int) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(effectNames.enumerated()), id: \.offset) { i, name in
                Button { onTap(i) } label: {
                    HStack {
                        Text(name).font(.caption).foregroundStyle(LiquidColors.Text.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(LiquidColors.Text.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Button("+ Add effect", action: onAdd)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiquidColors.Accent.amber)
                .buttonStyle(.plain)
        }
    }
}

// MARK: - InspectorLinkGroupSection (IM9-20)

/// Linked-clips indicator with link/unlink action.
struct InspectorLinkGroupSection: View {
    let isLinked: Bool
    let memberCount: Int
    let kindLabel: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isLinked ? "link" : "link.badge.plus")
                .foregroundStyle(LiquidColors.Accent.amber)
            if isLinked {
                Text("\(memberCount) linked clips\u00A0\u00B7\u00A0\(kindLabel)")
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
            } else {
                Text("Not linked")
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Text.tertiary)
            }
            Spacer()
            Button(isLinked ? "Unlink" : "Link", action: onToggle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiquidColors.Accent.amber)
                .buttonStyle(.plain)
        }
    }
}

// MARK: - InspectorClipMarkersSection (IM9-21)

/// Compact table of per-clip markers with color chip + label + timecode.
/// Tap to seek; swipe-to-delete (List native).
struct InspectorClipMarkersSection: View {
    struct Row: Identifiable {
        let id: String
        let label: String
        let timecode: String
        let colorName: String
    }

    let markers: [Row]
    let onTap: (Row) -> Void
    let onDelete: (Row) -> Void

    var body: some View {
        if markers.isEmpty {
            Text("No markers. Press M to add at playhead.")
                .font(.caption)
                .foregroundStyle(LiquidColors.Text.tertiary)
        } else {
            VStack(spacing: 2) {
                ForEach(markers) { marker in
                    Button { onTap(marker) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color(for: marker.colorName))
                                .frame(width: 8, height: 8)
                            Text(marker.label)
                                .font(.caption)
                                .foregroundStyle(LiquidColors.Text.primary)
                                .lineLimit(1)
                            Spacer()
                            Text(marker.timecode)
                                .font(.caption2.monospaced())
                                .foregroundStyle(LiquidColors.Text.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func color(for name: String) -> Color {
        switch name.lowercased() {
        case "red":    return LiquidColors.Accent.destructive
        case "green":  return LiquidColors.Accent.success
        case "blue":   return Color(red: 79/255, green: 195/255, blue: 247/255)
        case "purple": return Color(red: 170/255, green: 130/255, blue: 230/255)
        case "white":  return LiquidColors.Text.primary
        default:       return LiquidColors.Accent.amber
        }
    }
}

// MARK: - MixedValuePlaceholder (IM9-13 helper)

/// Em-dash placeholder shown by inspector rows in multi-select mode
/// when bound values disagree across the selection per spec §10.2.
struct MixedValuePlaceholder: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("\u2014")
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.tertiary)
            Text("Mixed")
                .font(.caption2)
                .foregroundStyle(LiquidColors.Text.tertiary)
        }
    }
}

