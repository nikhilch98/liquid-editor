import Foundation
import SwiftUI

/// Shared permission identifier used by `PermissionCoordinator` and
/// `PermissionPrimerSheet`. Each case carries copy, iconography, and a
/// short list of reasons the permission is requested.
enum PermissionKind: String, Sendable, Identifiable {
    case photoLibrary
    case camera
    case microphone

    var id: String { rawValue }

    /// SF Symbol for the primer illustration.
    var sfSymbol: String {
        switch self {
        case .photoLibrary: return "photo.on.rectangle.angled"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        }
    }

    /// Headline shown at the top of the primer sheet.
    var title: String {
        switch self {
        case .photoLibrary: return "Allow access to your photos"
        case .camera: return "Allow access to your camera"
        case .microphone: return "Allow access to your microphone"
        }
    }

    /// Subhead describing the user-facing benefit.
    var subtitle: String {
        switch self {
        case .photoLibrary: return "Liquid Editor can import videos and photos to use in your projects."
        case .camera: return "Liquid Editor can capture video and stills directly from your camera."
        case .microphone: return "Liquid Editor can record voice-overs and on-set audio."
        }
    }

    /// Bullet-point reasons listed under the subtitle.
    var rationale: [String] {
        switch self {
        case .photoLibrary:
            return [
                "Browse and import media into projects",
                "Save renders back to your photo library"
            ]
        case .camera:
            return [
                "Record new clips inside the editor",
                "Capture reference shots and stills"
            ]
        case .microphone:
            return [
                "Record voice-overs onto the timeline",
                "Capture sync-sound from external mics"
            ]
        }
    }
}
