import Foundation
import CoreGraphics
import Observation

// MARK: - FramingStyle

/// Framing style for subject positioning.
enum FramingStyle: String, Codable, CaseIterable, Sendable {
    /// Center subjects in frame.
    case centered

    /// Position subjects according to rule of thirds.
    case ruleOfThirds
}

// MARK: - AutoReframeConfig

/// Configuration for auto-reframe behavior.
///
/// Immutable value type controlling how the auto-reframe engine frames subjects.
struct AutoReframeConfig: Codable, Equatable, Sendable {
    /// How tightly to frame subjects (0.8 = loose, 2.0 = tight).
    let zoomIntensity: Double

    /// How quickly camera follows subjects (0.0 = very smooth, 1.0 = instant).
    let followSpeed: Double

    /// Extra padding around combined bounding box (0.0 - 0.3).
    let safeZonePadding: Double

    /// Maximum zoom level allowed.
    let maxZoom: Double

    /// Minimum zoom level (1.0 = no zoom out past original).
    let minZoom: Double

    /// Export aspect ratio (width / height). nil = use video's native ratio.
    let targetAspectRatio: Double?

    /// Framing style (centered or rule of thirds).
    let framingStyle: FramingStyle

    /// Look-ahead duration in milliseconds for predictive motion (0-500).
    let lookaheadMs: Int

    init(
        zoomIntensity: Double = 1.2,
        followSpeed: Double = 0.3,
        safeZonePadding: Double = 0.1,
        maxZoom: Double = 3.0,
        minZoom: Double = 1.0,
        targetAspectRatio: Double? = nil,
        framingStyle: FramingStyle = .centered,
        lookaheadMs: Int = 150
    ) {
        self.zoomIntensity = zoomIntensity
        self.followSpeed = followSpeed
        self.safeZonePadding = safeZonePadding
        self.maxZoom = maxZoom
        self.minZoom = minZoom
        self.targetAspectRatio = targetAspectRatio
        self.framingStyle = framingStyle
        self.lookaheadMs = lookaheadMs
    }

    /// Create a copy with optional overrides.
    func with(
        zoomIntensity: Double? = nil,
        followSpeed: Double? = nil,
        safeZonePadding: Double? = nil,
        maxZoom: Double? = nil,
        minZoom: Double? = nil,
        targetAspectRatio: Double?? = nil,
        framingStyle: FramingStyle? = nil,
        lookaheadMs: Int? = nil
    ) -> AutoReframeConfig {
        AutoReframeConfig(
            zoomIntensity: zoomIntensity ?? self.zoomIntensity,
            followSpeed: followSpeed ?? self.followSpeed,
            safeZonePadding: safeZonePadding ?? self.safeZonePadding,
            maxZoom: maxZoom ?? self.maxZoom,
            minZoom: minZoom ?? self.minZoom,
            targetAspectRatio: targetAspectRatio ?? self.targetAspectRatio,
            framingStyle: framingStyle ?? self.framingStyle,
            lookaheadMs: lookaheadMs ?? self.lookaheadMs
        )
    }
}

// MARK: - AutoReframeEngine

/// Engine that computes auto-reframe transforms based on person tracking data.
///
/// Generates smooth, temporal-coherent camera transforms to keep tracked subjects
/// in frame. Features adaptive smoothing (DanceFormer-inspired), dead zone filtering,
/// rule-of-thirds framing, and look-ahead prediction.
@Observable
@MainActor
final class AutoReframeEngine {

    // MARK: - Public Properties

    /// Current configuration.
    var config: AutoReframeConfig

    /// Whether auto-reframe is enabled.
    var isEnabled: Bool = false {
        didSet {
            if !isEnabled {
                smoothedTransform = nil
                lastStableTransform = nil
                transformHistory.removeAll()
                lastMotionDirection = .zero
                previousBbox = nil
            }
        }
    }

    /// Video aspect ratio (width / height).
    var videoAspectRatio: Double = 16.0 / 9.0

    // MARK: - Private Smoothing State

    /// Last smoothed transform (for temporal continuity).
    private var smoothedTransform: VideoTransform?

    /// Last stable transform (for dead zone comparison).
    private var lastStableTransform: VideoTransform?

    /// Transform history for adaptive smoothing (DanceFormer-inspired).
    private var transformHistory: [VideoTransform] = []

    /// Maximum history length.
    private static let maxHistoryLength = 10

    /// Last known motion direction for rule of thirds.
    private var lastMotionDirection: CGPoint = .zero

    /// Previous bounding box for motion direction computation.
    private var previousBbox: CGRect?

    // MARK: - Dead Zone Constants

    /// Translation dead zone: 4% of frame (dancers naturally sway/wobble).
    private static let translationDeadZone: Double = 0.04

    /// Scale dead zone: 6% scale change (zoom changes are intentional).
    private static let scaleDeadZone: Double = 0.06

    // MARK: - Initialization

    init(config: AutoReframeConfig = AutoReframeConfig()) {
        self.config = config
    }

    // MARK: - Public Methods

    /// Compute combined bounding box from list of person tracking results.
    ///
    /// Returns nil if no persons have visible bounding boxes.
    func computeCombinedBoundingBox(_ persons: [PersonTrackingResult]) -> CGRect? {
        if persons.isEmpty { return nil }

        var combined: CGRect?
        for person in persons {
            guard let bbox = person.boundingBox else { continue }

            // NormalizedBoundingBox uses CENTER coordinates (x, y are center point).
            // Convert to top-left origin for CGRect.
            let left = max(0.0, min(1.0, bbox.x - bbox.width / 2))
            let top = max(0.0, min(1.0, bbox.y - bbox.height / 2))
            let rect = CGRect(x: left, y: top, width: bbox.width, height: bbox.height)

            if let existing = combined {
                combined = existing.union(rect)
            } else {
                combined = rect
            }
        }

        return combined
    }

    /// Compute the target transform to center and frame the given bounding box.
    ///
    /// Ensures the bounding box stays within the visible viewport after transformation.
    func computeTargetTransform(_ combinedBbox: CGRect?) -> VideoTransform {
        guard let combinedBbox, !combinedBbox.isEmpty else {
            return smoothedTransform ?? .identity
        }

        // Add safe zone padding.
        let paddedBbox = CGRect(
            x: max(0.0, min(1.0, combinedBbox.minX - config.safeZonePadding)),
            y: max(0.0, min(1.0, combinedBbox.minY - config.safeZonePadding)),
            width: min(1.0, combinedBbox.width + config.safeZonePadding * 2),
            height: min(1.0, combinedBbox.height + config.safeZonePadding * 2)
        )

        let bboxWidth = paddedBbox.width
        let bboxHeight = paddedBbox.height

        let targetAspect = config.targetAspectRatio ?? videoAspectRatio
        let bboxAspect = bboxWidth / bboxHeight

        var scale: Double
        if bboxAspect > targetAspect {
            scale = (1.0 / bboxWidth) * config.zoomIntensity
        } else {
            scale = (1.0 / bboxHeight) * config.zoomIntensity * (targetAspect / videoAspectRatio)
        }

        // Clamp scale - also ensure we don't zoom so much that bbox is bigger than viewport.
        let maxDimension = max(bboxWidth, bboxHeight)
        let maxZoomToFitBbox = 1.0 / maxDimension
        let effectiveMaxZoom = min(config.maxZoom, maxZoomToFitBbox * 1.1)
        scale = max(config.minZoom, min(max(1.0, effectiveMaxZoom), scale))

        // Calculate translation to center the bbox.
        let bboxCenterX = paddedBbox.midX
        let bboxCenterY = paddedBbox.midY

        let targetX = (0.5 - bboxCenterX) * scale
        let targetY = (0.5 - bboxCenterY) * scale

        // Update motion direction for rule of thirds framing.
        computeMotionDirection(currentBbox: paddedBbox, previousBbox: previousBbox)
        previousBbox = paddedBbox

        // Apply rule of thirds offset if enabled.
        var finalTargetX = targetX
        var finalTargetY = targetY

        if config.framingStyle == .ruleOfThirds {
            let ruleOfThirdsOffset = calculateRuleOfThirdsOffset(lastMotionDirection)
            finalTargetX += ruleOfThirdsOffset.x * scale
            finalTargetY += ruleOfThirdsOffset.y * scale
        }

        // Compute translation limits to keep ENTIRE bounding box visible.
        let centerOffset = 0.5 * (scale - 1.0)

        let minTransX = max(-1.0, min(1.0, -paddedBbox.minX * scale + centerOffset))
        let maxTransX = max(-1.0, min(1.0, 1.0 - paddedBbox.maxX * scale + centerOffset))
        let minTransY = max(-1.0, min(1.0, -paddedBbox.minY * scale + centerOffset))
        let maxTransY = max(-1.0, min(1.0, 1.0 - paddedBbox.maxY * scale + centerOffset))

        // Ensure we don't show outside the video itself.
        let videoMaxTrans = abs(centerOffset)

        // Combine limits: ensure bbox is visible AND we don't show outside video.
        var finalMinX = max(-videoMaxTrans, min(videoMaxTrans, minTransX))
        var finalMaxX = max(-videoMaxTrans, min(videoMaxTrans, maxTransX))
        var finalMinY = max(-videoMaxTrans, min(videoMaxTrans, minTransY))
        var finalMaxY = max(-videoMaxTrans, min(videoMaxTrans, maxTransY))

        // Ensure min <= max (can become inverted after clamping to same range).
        if finalMinX > finalMaxX {
            let mid = (finalMinX + finalMaxX) / 2
            finalMinX = mid
            finalMaxX = mid
        }
        if finalMinY > finalMaxY {
            let mid = (finalMinY + finalMaxY) / 2
            finalMinY = mid
            finalMaxY = mid
        }

        // Clamp translation to computed limits.
        let clampedX = max(finalMinX, min(finalMaxX, finalTargetX))
        let clampedY = max(finalMinY, min(finalMaxY, finalTargetY))

        return VideoTransform(
            scale: scale,
            translation: CGPoint(x: clampedX, y: clampedY),
            rotation: 0.0
        )
    }

    /// Apply dead zone - only update if movement exceeds threshold.
    ///
    /// This prevents constant micro-adjustments that cause visual jitter.
    func applyDeadZone(_ targetTransform: VideoTransform) -> VideoTransform {
        guard let stable = lastStableTransform else {
            lastStableTransform = targetTransform
            return targetTransform
        }

        let dx = abs(targetTransform.translation.x - stable.translation.x)
        let dy = abs(targetTransform.translation.y - stable.translation.y)
        let dScale = abs(targetTransform.scale - stable.scale)
        let scaleRatio = dScale / stable.scale

        // Only update if movement is significant.
        if dx > Self.translationDeadZone || dy > Self.translationDeadZone || scaleRatio > Self.scaleDeadZone {
            lastStableTransform = targetTransform
            return targetTransform
        }

        // Otherwise, stick with the stable transform.
        return stable
    }

    /// Apply temporal smoothing with adaptive algorithm (DanceFormer-inspired).
    ///
    /// Adjusts smoothing based on movement velocity for better handling of dance movements.
    func applySmoothing(_ targetTransform: VideoTransform, deltaTime: Double = 1.0 / 30.0) -> VideoTransform {
        guard let current = smoothedTransform else {
            smoothedTransform = targetTransform
            addToHistory(targetTransform)
            return targetTransform
        }

        // Calculate movement velocity for adaptive smoothing.
        let velocity = calculateMovementVelocity()
        let alpha = calculateAdaptiveSmoothingFactor(velocity)

        // Apply adaptive smoothing.
        let scaleAlpha = alpha * 0.5 // Scale changes half as fast as translation.

        let smoothedScale = Self.lerp(current.scale, targetTransform.scale, scaleAlpha)
        let smoothedX = Self.lerp(current.translation.x, targetTransform.translation.x, alpha)
        let smoothedY = Self.lerp(current.translation.y, targetTransform.translation.y, alpha)
        let smoothedRotation = Self.lerp(current.rotation, targetTransform.rotation, alpha)

        let result = VideoTransform(
            scale: smoothedScale,
            translation: CGPoint(x: smoothedX, y: smoothedY),
            rotation: smoothedRotation
        )

        smoothedTransform = result
        addToHistory(result)
        return result
    }

    /// Get the auto-reframe transform for a given frame.
    func getTransformForFrame(
        _ frameResult: FrameTrackingResult?,
        selectedPersonIndices: Set<Int>
    ) -> VideoTransform {
        guard isEnabled, let frameResult else {
            return .identity
        }

        let selectedPersons = frameResult.people.filter {
            selectedPersonIndices.contains($0.personIndex)
        }

        let combinedBbox = computeCombinedBoundingBox(selectedPersons)
        let targetTransform = computeTargetTransform(combinedBbox)

        // Apply dead zone first, then smooth.
        let stableTransform = applyDeadZone(targetTransform)
        return applySmoothing(stableTransform)
    }

    /// Generate keyframes using event-driven approach (fewer, smarter keyframes).
    func generateKeyframes(
        trackingResults: [FrameTrackingResult],
        selectedPersonIndices: Set<Int>,
        videoDurationMicros: TimeMicros,
        keyframeIntervalMs: Int = 500
    ) -> [Keyframe] {
        if trackingResults.isEmpty || selectedPersonIndices.isEmpty {
            return []
        }

        // Reset smoothing for fresh generation.
        smoothedTransform = nil
        lastStableTransform = nil
        transformHistory.removeAll()
        lastMotionDirection = .zero
        previousBbox = nil

        var keyframes: [Keyframe] = []
        let intervalMs = keyframeIntervalMs
        let durationMs = Int(videoDurationMicros / 1_000)

        // Sort tracking results by timestamp.
        let sortedResults = trackingResults.sorted { $0.timestampMs < $1.timestampMs }

        var currentMs = 0
        var resultIndex = 0
        var lastKeyframeTransform: VideoTransform?

        // Threshold for creating a new keyframe (significant change).
        let translationThreshold: Double = 0.02 // 2% of frame
        let scaleThreshold: Double = 0.05 // 5% scale change

        while currentMs <= durationMs {
            // Find closest tracking result.
            while resultIndex < sortedResults.count - 1
                && sortedResults[resultIndex + 1].timestampMs <= currentMs
            {
                resultIndex += 1
            }

            // Calculate lookahead frame count from config (assuming ~30fps).
            let lookaheadFrameCount = max(1, min(15, Int(ceil(Double(config.lookaheadMs) / 33.0))))

            // Use lookahead averaging for smoother, predictive motion.
            let avgBbox = computeAveragedBbox(
                results: sortedResults,
                startIndex: resultIndex,
                count: lookaheadFrameCount,
                selectedPersonIndices: selectedPersonIndices
            )

            // Track motion direction for rule of thirds.
            var prevBbox: CGRect?
            if resultIndex > 0 {
                let prevFrame = sortedResults[resultIndex - 1]
                let prevPersons = prevFrame.people.filter {
                    selectedPersonIndices.contains($0.personIndex)
                }
                prevBbox = computeCombinedBoundingBox(prevPersons)
            }
            computeMotionDirection(currentBbox: avgBbox, previousBbox: prevBbox)

            // Compute target transform from averaged bbox.
            let targetTransform = computeTargetTransform(avgBbox)
            let stableTransform = applyDeadZone(targetTransform)
            let smoothedTransform = applySmoothing(stableTransform)

            // Determine if we should create a keyframe.
            var shouldCreateKeyframe = lastKeyframeTransform == nil
                || currentMs == 0
                || currentMs >= durationMs - intervalMs

            if !shouldCreateKeyframe, let lastKF = lastKeyframeTransform {
                // Check for significant change.
                let dx = abs(smoothedTransform.translation.x - lastKF.translation.x)
                let dy = abs(smoothedTransform.translation.y - lastKF.translation.y)
                let dScale = abs(smoothedTransform.scale - lastKF.scale) / lastKF.scale

                shouldCreateKeyframe = dx > translationThreshold
                    || dy > translationThreshold
                    || dScale > scaleThreshold
            }

            if shouldCreateKeyframe {
                let timestampMicros = TimeMicros(currentMs) * 1_000

                keyframes.append(Keyframe(
                    id: "auto_\(currentMs)",
                    timestampMicros: timestampMicros,
                    transform: smoothedTransform,
                    interpolation: .easeInOut,
                    label: "Auto"
                ))
                lastKeyframeTransform = smoothedTransform
            }

            currentMs += intervalMs
        }

        // Always ensure a keyframe at the end.
        if let lastKF = keyframes.last,
           Int(lastKF.timestampMicros / 1_000) < durationMs - 100
        {
            let lastResult = sortedResults.last
            let persons = (lastResult?.people ?? []).filter {
                selectedPersonIndices.contains($0.personIndex)
            }
            let bbox = computeCombinedBoundingBox(persons)
            let transform = computeTargetTransform(bbox)

            keyframes.append(Keyframe(
                id: "auto_\(durationMs)",
                timestampMicros: videoDurationMicros,
                transform: applySmoothing(applyDeadZone(transform)),
                interpolation: .easeInOut,
                label: "Auto"
            ))
        }

        return keyframes
    }

    /// Reset the engine state.
    func reset() {
        smoothedTransform = nil
        lastStableTransform = nil
        transformHistory.removeAll()
        lastMotionDirection = .zero
        previousBbox = nil
    }

    // MARK: - Private Methods

    /// Calculate movement velocity from recent transform history (DanceFormer-inspired).
    private func calculateMovementVelocity() -> Double {
        guard transformHistory.count >= 3 else { return 0.0 }

        var totalVelocity: Double = 0.0
        var count = 0

        for i in 1..<transformHistory.count {
            let prev = transformHistory[i - 1]
            let curr = transformHistory[i]

            let dx = curr.translation.x - prev.translation.x
            let dy = curr.translation.y - prev.translation.y
            let velocity = sqrt(dx * dx + dy * dy)

            totalVelocity += velocity
            count += 1
        }

        return count > 0 ? totalVelocity / Double(count) : 0.0
    }

    /// Calculate adaptive smoothing factor based on movement velocity (DanceFormer insight).
    ///
    /// Fast movements need less smoothing, slow movements need more.
    private func calculateAdaptiveSmoothingFactor(_ velocity: Double) -> Double {
        // Velocity thresholds (empirically tuned for dance).
        let slowThreshold: Double = 0.005 // Very slow movement (ballet adagio)
        let fastThreshold: Double = 0.03 // Very fast movement (hip-hop popping)

        // Map velocity to smoothing intensity.
        let velocityFactor: Double
        if velocity < slowThreshold {
            velocityFactor = 1.0 // Maximum smoothing for slow movements
        } else if velocity > fastThreshold {
            velocityFactor = 0.0 // Minimum smoothing for fast movements
        } else {
            // Linear interpolation between thresholds.
            velocityFactor = 1.0 - (velocity - slowThreshold) / (fastThreshold - slowThreshold)
        }

        // Convert to alpha: high factor -> high alpha (more smoothing).
        // Range: 0.2 (fast) to 0.8 (slow).
        let adaptiveAlpha = 0.2 + (velocityFactor * 0.6)

        // Blend with user's followSpeed preference (60% adaptive, 40% user).
        let userFactor = 0.05 + (config.followSpeed * 0.15)
        let blendedAlpha = adaptiveAlpha * 0.6 + userFactor * 0.4

        return max(0.05, min(0.5, blendedAlpha))
    }

    /// Add transform to history for adaptive smoothing.
    private func addToHistory(_ transform: VideoTransform) {
        transformHistory.append(transform)
        if transformHistory.count > Self.maxHistoryLength {
            transformHistory.removeFirst()
        }
    }

    /// Compute motion direction from recent bounding box positions.
    @discardableResult
    private func computeMotionDirection(
        currentBbox: CGRect?,
        previousBbox: CGRect?
    ) -> CGPoint {
        guard let currentBbox, let previousBbox else {
            return lastMotionDirection
        }

        let dx = currentBbox.midX - previousBbox.midX
        let dy = currentBbox.midY - previousBbox.midY

        // Only update if movement is significant.
        if abs(dx) > 0.01 || abs(dy) > 0.01 {
            lastMotionDirection = CGPoint(x: dx, y: dy)
        }

        return lastMotionDirection
    }

    /// Calculate target position offset for rule of thirds framing.
    private func calculateRuleOfThirdsOffset(_ motionDirection: CGPoint) -> CGPoint {
        // Place subject on opposite third from motion direction.
        // Moving right -> place on left third (offset positive, moves frame left).
        // Moving left -> place on right third (offset negative, moves frame right).

        var xOffset: Double = 0.0
        if motionDirection.x > 0.005 {
            // Moving right, place subject at left third.
            xOffset = 0.12 // ~1/6 of frame to position at 1/3
        } else if motionDirection.x < -0.005 {
            // Moving left, place subject at right third.
            xOffset = -0.12
        }

        // Slight upward bias for more pleasing framing.
        let yOffset: Double = -0.03

        return CGPoint(x: xOffset, y: yOffset)
    }

    /// Compute average bounding box from multiple frames (lookahead averaging).
    private func computeAveragedBbox(
        results: [FrameTrackingResult],
        startIndex: Int,
        count: Int,
        selectedPersonIndices: Set<Int>
    ) -> CGRect? {
        if results.isEmpty { return nil }

        var sumLeft: Double = 0
        var sumTop: Double = 0
        var sumRight: Double = 0
        var sumBottom: Double = 0
        var validCount = 0

        for i in 0..<count where startIndex + i < results.count {
            let frame = results[startIndex + i]
            let persons = frame.people.filter {
                selectedPersonIndices.contains($0.personIndex)
            }
            guard let bbox = computeCombinedBoundingBox(persons) else { continue }

            sumLeft += bbox.minX
            sumTop += bbox.minY
            sumRight += bbox.maxX
            sumBottom += bbox.maxY
            validCount += 1
        }

        guard validCount > 0 else { return nil }

        let avgLeft = sumLeft / Double(validCount)
        let avgTop = sumTop / Double(validCount)
        let avgRight = sumRight / Double(validCount)
        let avgBottom = sumBottom / Double(validCount)

        return CGRect(
            x: avgLeft,
            y: avgTop,
            width: avgRight - avgLeft,
            height: avgBottom - avgTop
        )
    }

    /// Linear interpolation between two values.
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
