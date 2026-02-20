//
//  AppearanceFeature.swift
//  LiquidEditor
//
//  512-dimensional appearance embedding for person re-identification.
//  Used to match people who reappear after being lost from tracking.
//
//  Enhanced with multi-view support for dance videos:
//  - Stores orientation-specific embeddings (front, back, side)
//  - Cross-compares views for robust matching during rotations
//
//

import Accelerate
import CoreGraphics
import Foundation

// MARK: - Body Orientation

/// Detected body orientation based on keypoint analysis.
enum BodyOrientation: String, Codable, Sendable {
    case front       // Facing camera
    case back        // Facing away from camera
    case leftSide    // Left profile visible
    case rightSide   // Right profile visible
    case unknown     // Cannot determine orientation

    // MARK: - Orientation Detection Thresholds

    private static let shoulderVisibilityThreshold: Float = 0.3
    private static let narrowShoulderWidthThreshold: CGFloat = 0.03
    private static let noseVisibilityThreshold: Float = 0.2
    private static let noseCenteringThreshold: CGFloat = 0.5

    /// Detect orientation from COCO keypoints.
    /// - Parameter keypoints: Array of 17 COCO keypoints with confidence scores.
    /// - Returns: Detected body orientation.
    static func detect(from keypoints: [(point: CGPoint, confidence: Float)]?) -> BodyOrientation {
        guard let kps = keypoints, kps.count >= 17 else {
            return .unknown
        }

        let noseIdx = 0
        let leftShoulderIdx = 5
        let rightShoulderIdx = 6

        let nose = kps[noseIdx]
        let leftShoulder = kps[leftShoulderIdx]
        let rightShoulder = kps[rightShoulderIdx]

        let shouldersVisible = leftShoulder.confidence > shoulderVisibilityThreshold &&
                              rightShoulder.confidence > shoulderVisibilityThreshold

        guard shouldersVisible else {
            return .unknown
        }

        let shoulderWidth = abs(leftShoulder.point.x - rightShoulder.point.x)
        let shoulderCenter = (leftShoulder.point.x + rightShoulder.point.x) / 2

        // Very narrow shoulders = side view
        if shoulderWidth < narrowShoulderWidthThreshold {
            if nose.confidence > shoulderVisibilityThreshold {
                return nose.point.x > shoulderCenter ? .rightSide : .leftSide
            }
            return leftShoulder.confidence > rightShoulder.confidence ? .leftSide : .rightSide
        }

        // Check nose visibility for front vs back
        if nose.confidence < noseVisibilityThreshold {
            return .back
        }

        // Nose visible with wide shoulders = front view
        let noseRelativeToShoulders = nose.point.x - shoulderCenter
        if abs(noseRelativeToShoulders) < shoulderWidth * noseCenteringThreshold {
            return .front
        }

        return noseRelativeToShoulders > 0 ? .rightSide : .leftSide
    }
}

// MARK: - AppearanceFeature

/// 512-dimensional appearance embedding for a tracked person.
struct AppearanceFeature: Sendable {

    /// Normalized 512-dim feature vector (L2 normalized).
    let embedding: [Float]

    /// Quality score of the embedding (0-1), based on bounding box quality.
    let qualityScore: Float

    /// Dimension of the embedding vector.
    static let dimension = 512

    /// Threshold for cosine similarity to consider a match.
    static let reidThreshold: Float = 0.65

    /// High confidence threshold -- skip spatial checks entirely.
    static let highConfidenceThreshold: Float = 0.78

    /// Medium confidence threshold for long-gap matching.
    static let mediumConfidenceThreshold: Float = 0.68

    /// Alpha for exponential moving average when updating appearance.
    static let updateAlpha: Float = 0.8

    // MARK: - Initialization

    init(embedding: [Float], qualityScore: Float = 1.0) {
        precondition(embedding.count == Self.dimension,
                     "Embedding must be \(Self.dimension)-dimensional")
        self.embedding = Self.normalize(embedding)
        self.qualityScore = qualityScore
    }

    /// Create from raw model output (will be normalized).
    init(rawEmbedding: [Float], qualityScore: Float = 1.0) {
        precondition(rawEmbedding.count == Self.dimension,
                     "Raw embedding must be \(Self.dimension)-dimensional")
        self.embedding = Self.normalize(rawEmbedding)
        self.qualityScore = qualityScore
    }

    // MARK: - Similarity

    /// Compute cosine similarity with another embedding.
    /// Returns value in range [-1, 1], where 1 = identical.
    func cosineSimilarity(with other: AppearanceFeature) -> Float {
        // Since embeddings are already normalized, cosine similarity = dot product
        var result: Float = 0
        vDSP_dotpr(embedding, 1, other.embedding, 1, &result, vDSP_Length(Self.dimension))
        return result
    }

    /// Check if this embedding matches another (above threshold).
    func matches(_ other: AppearanceFeature, threshold: Float = reidThreshold) -> Bool {
        cosineSimilarity(with: other) >= threshold
    }

    // MARK: - Update

    /// Create updated appearance by blending with new observation.
    /// Uses exponential moving average: new = alpha * old + (1-alpha) * observation.
    func updated(with observation: AppearanceFeature, alpha: Float = updateAlpha) -> AppearanceFeature {
        var blended = [Float](repeating: 0, count: Self.dimension)

        var alphaVal = alpha
        var oneMinusAlpha = 1.0 - alpha

        vDSP_vsma(embedding, 1, &alphaVal, blended, 1, &blended, 1, vDSP_Length(Self.dimension))
        vDSP_vsma(observation.embedding, 1, &oneMinusAlpha, blended, 1, &blended, 1, vDSP_Length(Self.dimension))

        let newQuality = max(qualityScore, observation.qualityScore)
        return AppearanceFeature(rawEmbedding: blended, qualityScore: newQuality)
    }

    // MARK: - Normalization

    /// Epsilon for L2 normalization to avoid division by zero.
    private static let normalizationEpsilon: Float = 1e-6

    /// L2 normalize a vector.
    private static func normalize(_ vector: [Float]) -> [Float] {
        var result = vector
        var sumOfSquares: Float = 0
        vDSP_dotpr(vector, 1, vector, 1, &sumOfSquares, vDSP_Length(vector.count))

        let magnitude = sqrt(sumOfSquares)
        if magnitude > normalizationEpsilon {
            var scale = 1.0 / magnitude
            vDSP_vsmul(vector, 1, &scale, &result, 1, vDSP_Length(vector.count))
        }

        return result
    }
}

// MARK: - Codable

extension AppearanceFeature: Codable {
    enum CodingKeys: String, CodingKey {
        case embedding
        case qualityScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawEmbedding = try container.decode([Float].self, forKey: .embedding)
        let quality = try container.decodeIfPresent(Float.self, forKey: .qualityScore) ?? 1.0
        self.init(rawEmbedding: rawEmbedding, qualityScore: quality)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(embedding, forKey: .embedding)
        try container.encode(qualityScore, forKey: .qualityScore)
    }
}

// MARK: - Multi-View Appearance

/// Multi-view appearance storage for robust matching across body orientations.
/// Stores separate embeddings for front, back, and side views to handle
/// dancers rotating 180 degrees during performance.
///
/// Thread Safety: `@unchecked Sendable` because mutable state is
/// protected by `NSLock` for thread-safe access.
final class MultiViewAppearance: @unchecked Sendable {

    /// Primary embedding (most recent high-quality, EMA-smoothed).
    private(set) var primaryEmbedding: AppearanceFeature?

    /// Orientation-specific embeddings.
    private var frontEmbedding: AppearanceFeature?
    private var backEmbedding: AppearanceFeature?
    private var sideEmbedding: AppearanceFeature?  // Combined left/right side

    /// Quality threshold for storing orientation-specific embeddings.
    private static let orientationQualityThreshold: Float = 0.6

    /// Lock for thread safety.
    private let lock = NSLock()

    init() {}

    /// Initialize with an existing appearance feature.
    init(appearance: AppearanceFeature, orientation: BodyOrientation = .unknown) {
        self.primaryEmbedding = appearance
        storeForOrientation(appearance, orientation: orientation)
    }

    // MARK: - Update

    /// Update with a new appearance observation.
    /// - Parameters:
    ///   - appearance: New appearance embedding.
    ///   - orientation: Detected body orientation.
    func update(with appearance: AppearanceFeature, orientation: BodyOrientation) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = primaryEmbedding {
            primaryEmbedding = existing.updated(with: appearance)
        } else {
            primaryEmbedding = appearance
        }

        if appearance.qualityScore >= Self.orientationQualityThreshold {
            storeForOrientation(appearance, orientation: orientation)
        }
    }

    private func storeForOrientation(_ appearance: AppearanceFeature, orientation: BodyOrientation) {
        switch orientation {
        case .front:
            if frontEmbedding == nil || appearance.qualityScore > (frontEmbedding?.qualityScore ?? 0) {
                frontEmbedding = appearance
            }
        case .back:
            if backEmbedding == nil || appearance.qualityScore > (backEmbedding?.qualityScore ?? 0) {
                backEmbedding = appearance
            }
        case .leftSide, .rightSide:
            if sideEmbedding == nil || appearance.qualityScore > (sideEmbedding?.qualityScore ?? 0) {
                sideEmbedding = appearance
            }
        case .unknown:
            break
        }
    }

    // MARK: - Similarity

    /// Compute best similarity across all stored views.
    /// Returns the maximum similarity found between any view pair.
    func bestSimilarity(with other: MultiViewAppearance) -> Float {
        lock.lock()
        defer { lock.unlock() }

        var bestSim: Float = 0

        let selfEmbeddings = [primaryEmbedding, frontEmbedding, backEmbedding, sideEmbedding].compactMap { $0 }
        let otherEmbeddings = [other.primaryEmbedding, other.frontEmbedding, other.backEmbedding, other.sideEmbedding].compactMap { $0 }

        for e1 in selfEmbeddings {
            for e2 in otherEmbeddings {
                let sim = e1.cosineSimilarity(with: e2)
                bestSim = max(bestSim, sim)
            }
        }

        return bestSim
    }

    /// Compute similarity with a single appearance feature.
    /// Compares against all stored views and returns the best match.
    func bestSimilarity(with appearance: AppearanceFeature) -> Float {
        lock.lock()
        defer { lock.unlock() }

        var bestSim: Float = 0

        let embeddings = [primaryEmbedding, frontEmbedding, backEmbedding, sideEmbedding].compactMap { $0 }

        for e in embeddings {
            let sim = e.cosineSimilarity(with: appearance)
            bestSim = max(bestSim, sim)
        }

        return bestSim
    }

    /// Get the primary appearance feature for archiving.
    var appearanceForArchive: AppearanceFeature? {
        lock.lock()
        defer { lock.unlock() }
        return primaryEmbedding
    }

    /// Check if any embeddings are stored.
    var hasEmbeddings: Bool {
        lock.lock()
        defer { lock.unlock() }
        return primaryEmbedding != nil
    }

    /// Number of orientation-specific views stored.
    var viewCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return [frontEmbedding, backEmbedding, sideEmbedding].compactMap { $0 }.count
    }
}
