// PeopleService.swift
// LiquidEditor
//
// People library management service.
// Handles person detection via Vision framework, image quality assessment,
// and embedding extraction for re-identification.

import Accelerate
import CoreImage
import CoreVideo
import Foundation
import os
import UIKit
import Vision

// MARK: - DuplicateCheckResult

/// Result of a duplicate check operation.
struct DuplicateCheckResult: Sendable {
    let isDuplicate: Bool
    let matchedPersonId: String?
    let matchedPersonName: String?
    let similarity: Float
    let topMatches: [SimilarityDetail]

    init(
        isDuplicate: Bool,
        matchedPersonId: String? = nil,
        matchedPersonName: String? = nil,
        similarity: Float = 0,
        topMatches: [SimilarityDetail] = []
    ) {
        self.isDuplicate = isDuplicate
        self.matchedPersonId = matchedPersonId
        self.matchedPersonName = matchedPersonName
        self.similarity = similarity
        self.topMatches = topMatches
    }
}

// MARK: - SimilarityDetail

/// Detail of a similarity comparison.
struct SimilarityDetail: Sendable {
    let personId: String
    let personName: String
    let similarity: Float
}

// MARK: - PersonEmbedding

/// Embedding data for a known person.
struct PersonEmbedding: Sendable {
    let id: String
    let name: String
    let embeddings: [EmbeddingEntry]
}

// MARK: - AddImageValidationResult

/// Result of validating a new image for an existing person.
struct AddImageValidationResult: Sendable {
    let isValid: Bool
    let warningMessage: String?
    let betterMatchPersonId: String?
    let betterMatchPersonName: String?
    let betterMatchSimilarity: Float?

    init(
        isValid: Bool,
        warningMessage: String? = nil,
        betterMatchPersonId: String? = nil,
        betterMatchPersonName: String? = nil,
        betterMatchSimilarity: Float? = nil
    ) {
        self.isValid = isValid
        self.warningMessage = warningMessage
        self.betterMatchPersonId = betterMatchPersonId
        self.betterMatchPersonName = betterMatchPersonName
        self.betterMatchSimilarity = betterMatchSimilarity
    }
}

// MARK: - ImageQualityAssessment

/// Result of image quality assessment.
struct ImageQualityAssessment: Sendable {
    let isAcceptable: Bool
    let errorType: PersonDetectionError?
    let errorMessage: String?

    init(
        isAcceptable: Bool,
        errorType: PersonDetectionError? = nil,
        errorMessage: String? = nil
    ) {
        self.isAcceptable = isAcceptable
        self.errorType = errorType
        self.errorMessage = errorMessage
    }
}

// MARK: - PeopleService

/// Service for People library operations.
///
/// Thread Safety:
/// - `actor` ensures serial access to mutable state.
/// - Vision framework requests are dispatched on background threads.
/// - CIContext is Metal-backed and thread-safe.
actor PeopleService {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "PeopleService")

    // MARK: - Properties

    private let ciContext: CIContext

    /// Duplicate detection threshold (cosine similarity).
    private let duplicateThreshold: Float

    /// Weak match warning threshold.
    private let weakMatchThreshold: Float

    /// Minimum image dimension for processing.
    private let minImageDimension: CGFloat

    /// Minimum brightness for acceptable image.
    private let minBrightness: Float

    // MARK: - Init

    /// Initialize the PeopleService with configurable thresholds.
    ///
    /// - Parameters:
    ///   - duplicateThreshold: Cosine similarity threshold for duplicate detection (default: 0.70).
    ///   - weakMatchThreshold: Cosine similarity threshold for weak match warnings (default: 0.55).
    ///   - minImageDimension: Minimum image dimension in pixels (default: 200).
    ///   - minBrightness: Minimum brightness threshold (default: 0.15).
    init(
        duplicateThreshold: Float = 0.70,
        weakMatchThreshold: Float = 0.55,
        minImageDimension: CGFloat = 200,
        minBrightness: Float = 0.15
    ) {
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        self.duplicateThreshold = duplicateThreshold
        self.weakMatchThreshold = weakMatchThreshold
        self.minImageDimension = minImageDimension
        self.minBrightness = minBrightness
    }

    // MARK: - Detection

    /// Detect all people in an image using Vision framework.
    ///
    /// - Parameter imagePath: Absolute path to the image file.
    /// - Returns: Detection result with person data and embeddings.
    func detectPeople(imagePath: String) async -> PersonDetectionResult {
        guard let uiImage = UIImage(contentsOfFile: imagePath) else {
            return PersonDetectionResult(
                success: false,
                errorMessage: "Could not load image from path",
                errorType: .invalidImage
            )
        }

        guard let ciImage = CIImage(image: uiImage) else {
            return PersonDetectionResult(
                success: false,
                errorMessage: "Could not create CIImage",
                errorType: .invalidImage
            )
        }

        // Assess image quality
        let quality = assessImageQuality(ciImage)
        if !quality.isAcceptable {
            return PersonDetectionResult(
                success: false,
                errorMessage: quality.errorMessage ?? "Image quality check failed",
                errorType: quality.errorType ?? .detectionFailed
            )
        }

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return PersonDetectionResult(
                success: false,
                errorMessage: "Could not create CGImage",
                errorType: .detectionFailed
            )
        }

        // Run Vision framework face detection
        let detections = await detectFacesWithVision(cgImage: cgImage)

        if detections.isEmpty {
            return PersonDetectionResult(
                success: false,
                errorMessage: "No face found in image. Please use a photo showing a clear face.",
                errorType: .noPersonDetected
            )
        }

        var people: [DetectedPerson] = []
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        for (index, detection) in detections.enumerated() {
            // Convert Vision's bottom-left origin to top-left origin
            let faceBox = CGRect(
                x: detection.boundingBox.origin.x,
                y: 1 - detection.boundingBox.origin.y - detection.boundingBox.height,
                width: detection.boundingBox.width,
                height: detection.boundingBox.height
            )

            // Use face box for pixel coordinates
            let pixelFaceBox = CGRect(
                x: faceBox.origin.x * imageSize.width,
                y: faceBox.origin.y * imageSize.height,
                width: faceBox.width * imageSize.width,
                height: faceBox.height * imageSize.height
            )

            // Quality score based on face size relative to image
            let faceArea = faceBox.width * faceBox.height
            let qualityScore = min(Double(faceArea * 10), 1.0)

            people.append(DetectedPerson(
                id: "person_\(index)",
                boundingBox: pixelFaceBox,
                confidence: Double(detection.confidence),
                embedding: [],
                qualityScore: qualityScore
            ))
        }

        // Appearance embeddings require an OSNet ReID model which is not yet
        // bundled with the app. Callers that rely on embeddings (duplicate
        // detection, cross-session Re-ID) will see `embedding == []` and
        // skip those code paths. Logged once per detection so the gap is
        // visible in telemetry rather than silent.
        Self.logger.info("Face embeddings unavailable (OSNet model not loaded); duplicate detection skipped")

        return PersonDetectionResult(
            success: true,
            personCount: people.count,
            people: people
        )
    }

    // MARK: - Face Detection via Vision

    private func detectFacesWithVision(
        cgImage: CGImage
    ) async -> [(boundingBox: CGRect, confidence: Float)] {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let detections = observations.map { observation in
                    (boundingBox: observation.boundingBox, confidence: observation.confidence)
                }
                continuation.resume(returning: detections)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Self.logger.error("Face detection failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Duplicate Check

    /// Check if a new embedding matches any existing person.
    ///
    /// - Parameters:
    ///   - newEmbedding: The embedding vector to check.
    ///   - peopleData: Existing people with their embeddings.
    /// - Returns: Duplicate check result with similarity scores.
    func findDuplicates(
        newEmbedding: [Double],
        peopleData: [PersonEmbedding]
    ) -> DuplicateCheckResult {
        guard !peopleData.isEmpty else {
            return DuplicateCheckResult(isDuplicate: false, similarity: 0)
        }

        var matches: [(personId: String, personName: String, bestSimilarity: Float)] = []

        for person in peopleData {
            var bestSimilarity: Float = 0

            for entry in person.embeddings {
                let similarity = cosineSimilarity(newEmbedding, entry.embedding)
                bestSimilarity = max(bestSimilarity, similarity)
            }

            matches.append((person.id, person.name, bestSimilarity))
        }

        matches.sort { $0.bestSimilarity > $1.bestSimilarity }

        let topMatches = matches.prefix(3).map { match in
            SimilarityDetail(
                personId: match.personId,
                personName: match.personName,
                similarity: match.bestSimilarity
            )
        }

        guard let bestMatch = matches.first else {
            return DuplicateCheckResult(isDuplicate: false, similarity: 0)
        }

        let isDuplicate = bestMatch.bestSimilarity >= duplicateThreshold

        return DuplicateCheckResult(
            isDuplicate: isDuplicate,
            matchedPersonId: isDuplicate ? bestMatch.personId : nil,
            matchedPersonName: isDuplicate ? bestMatch.personName : nil,
            similarity: bestMatch.bestSimilarity,
            topMatches: Array(topMatches)
        )
    }

    // MARK: - Add to Existing Validation

    /// Validate that a new image belongs to the target person.
    ///
    /// - Parameters:
    ///   - newEmbedding: Embedding of the new image.
    ///   - targetPersonId: ID of the target person.
    ///   - allPeopleData: All people with their embeddings.
    /// - Returns: Validation result.
    func validateAddToExisting(
        newEmbedding: [Double],
        targetPersonId: String,
        allPeopleData: [PersonEmbedding]
    ) -> AddImageValidationResult {
        var targetSimilarity: Float = 0
        var bestOtherMatch: (id: String, name: String, similarity: Float)?

        for person in allPeopleData {
            var bestSimilarity: Float = 0

            for entry in person.embeddings {
                let sim = cosineSimilarity(newEmbedding, entry.embedding)
                bestSimilarity = max(bestSimilarity, sim)
            }

            if person.id == targetPersonId {
                targetSimilarity = bestSimilarity
            } else if bestOtherMatch == nil || bestSimilarity > bestOtherMatch!.similarity {
                bestOtherMatch = (person.id, person.name, bestSimilarity)
            }
        }

        if let other = bestOtherMatch,
           other.similarity > targetSimilarity + 0.1,
           other.similarity >= duplicateThreshold {
            return AddImageValidationResult(
                isValid: false,
                warningMessage: "This looks more like \(other.name)",
                betterMatchPersonId: other.id,
                betterMatchPersonName: other.name,
                betterMatchSimilarity: other.similarity
            )
        }

        if targetSimilarity < weakMatchThreshold {
            return AddImageValidationResult(
                isValid: true,
                warningMessage: "Low similarity - this might be a different pose or angle"
            )
        }

        return AddImageValidationResult(isValid: true)
    }

    // MARK: - Image Quality Assessment

    private func assessImageQuality(_ image: CIImage) -> ImageQualityAssessment {
        let extent = image.extent

        if extent.width < minImageDimension || extent.height < minImageDimension {
            return ImageQualityAssessment(
                isAcceptable: false,
                errorType: .imageTooSmall,
                errorMessage: "Image is too small. Please use a larger photo."
            )
        }

        guard let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ]),
              let outputImage = avgFilter.outputImage else {
            return ImageQualityAssessment(isAcceptable: true)
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let brightness = (Float(bitmap[0]) + Float(bitmap[1]) + Float(bitmap[2])) / (3.0 * 255.0)

        if brightness < minBrightness {
            return ImageQualityAssessment(
                isAcceptable: false,
                errorType: .imageTooDark,
                errorMessage: "Image is too dark. Please use a well-lit photo."
            )
        }

        return ImageQualityAssessment(isAcceptable: true)
    }

    // MARK: - Math Utilities

    /// Compute cosine similarity between two embedding vectors using Accelerate.
    ///
    /// Uses vDSP for SIMD-accelerated dot product and sum-of-squares operations.
    ///
    /// - Parameters:
    ///   - a: First embedding vector.
    ///   - b: Second embedding vector.
    /// - Returns: Cosine similarity in range [0, 1], or 0 if vectors are invalid.
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Double = 0
        var normASquared: Double = 0
        var normBSquared: Double = 0

        // Compute dot product using vDSP
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        // Compute sum of squares for norm calculations
        vDSP_svesqD(a, 1, &normASquared, vDSP_Length(a.count))
        vDSP_svesqD(b, 1, &normBSquared, vDSP_Length(b.count))

        let denominator = sqrt(normASquared) * sqrt(normBSquared)
        guard denominator > 0 else { return 0 }

        return Float(dotProduct / denominator)
    }
}
