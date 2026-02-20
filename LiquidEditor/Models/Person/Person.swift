import Foundation
import CoreGraphics

// MARK: - Person

/// A known person in the People library.
struct Person: Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let images: [PersonImage]

    /// Best embedding for quick comparison (highest quality image's embedding).
    /// Returns `nil` when no images are available.
    var primaryEmbedding: [Double]? {
        guard let best = images.max(by: { $0.qualityScore < $1.qualityScore }) else {
            return nil
        }
        return best.embedding
    }

    /// All embeddings for comprehensive matching.
    var allEmbeddings: [[Double]] {
        images.map(\.embedding)
    }

    /// Thumbnail path (first image).
    var thumbnailPath: String {
        images.isEmpty ? "" : images.first!.imagePath
    }

    /// Number of reference images.
    var imageCount: Int { images.count }

    /// Check if can add more images (max 5).
    var canAddMoreImages: Bool { images.count < 5 }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        name: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        images: [PersonImage]? = nil
    ) -> Person {
        Person(
            id: id ?? self.id,
            name: name ?? self.name,
            createdAt: createdAt ?? self.createdAt,
            modifiedAt: modifiedAt ?? self.modifiedAt,
            images: images ?? self.images
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: Person, rhs: Person) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - PersonImage

/// A reference image for a person.
struct PersonImage: Codable, Equatable, Hashable, Sendable {
    let id: String
    let imagePath: String
    let embedding: [Double]
    let qualityScore: Double
    let addedAt: Date
    let boundingBox: CGRect?

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        imagePath: String? = nil,
        embedding: [Double]? = nil,
        qualityScore: Double? = nil,
        addedAt: Date? = nil,
        boundingBox: CGRect?? = nil
    ) -> PersonImage {
        PersonImage(
            id: id ?? self.id,
            imagePath: imagePath ?? self.imagePath,
            embedding: embedding ?? self.embedding,
            qualityScore: qualityScore ?? self.qualityScore,
            addedAt: addedAt ?? self.addedAt,
            boundingBox: boundingBox ?? self.boundingBox
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, imagePath, embedding, qualityScore, addedAt, boundingBox
    }

    init(
        id: String,
        imagePath: String,
        embedding: [Double],
        qualityScore: Double,
        addedAt: Date,
        boundingBox: CGRect? = nil
    ) {
        self.id = id
        self.imagePath = imagePath
        self.embedding = embedding
        self.qualityScore = qualityScore
        self.addedAt = addedAt
        self.boundingBox = boundingBox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        embedding = try container.decode([Double].self, forKey: .embedding)
        qualityScore = try container.decode(Double.self, forKey: .qualityScore)
        let dateStr = try container.decode(String.self, forKey: .addedAt)
        addedAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()

        if let bb = try container.decodeIfPresent(CodableBoundingBox.self, forKey: .boundingBox) {
            boundingBox = CGRect(x: bb.x, y: bb.y, width: bb.width, height: bb.height)
        } else {
            boundingBox = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(embedding, forKey: .embedding)
        try container.encode(qualityScore, forKey: .qualityScore)
        try container.encode(ISO8601DateFormatter().string(from: addedAt), forKey: .addedAt)

        if let bb = boundingBox {
            let codable = CodableBoundingBox(x: bb.origin.x, y: bb.origin.y, width: bb.width, height: bb.height)
            try container.encode(codable, forKey: .boundingBox)
        }
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: PersonImage, rhs: PersonImage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - PersonDetectionError

/// Error types for person detection.
enum PersonDetectionError: String, Codable, CaseIterable, Sendable {
    case invalidImage
    case noPersonDetected
    case detectionFailed
    case embeddingFailed
    case imageTooSmall
    case imageTooDark
}

// MARK: - PersonDetectionResult

/// Result of person detection in an image.
struct PersonDetectionResult: Codable, Equatable, Hashable, Sendable {
    let success: Bool
    let personCount: Int
    let people: [DetectedPerson]
    let errorMessage: String?
    let errorType: PersonDetectionError?

    init(
        success: Bool,
        personCount: Int = 0,
        people: [DetectedPerson] = [],
        errorMessage: String? = nil,
        errorType: PersonDetectionError? = nil
    ) {
        self.success = success
        self.personCount = personCount
        self.people = people
        self.errorMessage = errorMessage
        self.errorType = errorType
    }
}

// MARK: - DetectedPerson

/// A person detected in an image (before being added to library).
struct DetectedPerson: Codable, Equatable, Hashable, Sendable {
    let id: String
    let boundingBox: CGRect
    let confidence: Double
    let embedding: [Double]
    let qualityScore: Double

    /// Get quality rating label.
    var qualityLabel: String {
        if qualityScore >= 0.85 { return "Excellent" }
        if qualityScore >= 0.70 { return "Great" }
        if qualityScore >= 0.50 { return "Good" }
        if qualityScore >= 0.30 { return "Fair" }
        return "Poor"
    }

    /// Get quality star count (1-5).
    var qualityStars: Int {
        if qualityScore >= 0.85 { return 5 }
        if qualityScore >= 0.70 { return 4 }
        if qualityScore >= 0.50 { return 3 }
        if qualityScore >= 0.30 { return 2 }
        return 1
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, boundingBox, confidence, embedding, qualityScore
    }

    init(
        id: String,
        boundingBox: CGRect,
        confidence: Double,
        embedding: [Double],
        qualityScore: Double
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.embedding = embedding
        self.qualityScore = qualityScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let bb = try container.decode(CodableBoundingBox.self, forKey: .boundingBox)
        boundingBox = CGRect(x: bb.x, y: bb.y, width: bb.width, height: bb.height)
        confidence = try container.decode(Double.self, forKey: .confidence)
        embedding = try container.decode([Double].self, forKey: .embedding)
        qualityScore = try container.decode(Double.self, forKey: .qualityScore)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        let bb = CodableBoundingBox(
            x: boundingBox.origin.x,
            y: boundingBox.origin.y,
            width: boundingBox.width,
            height: boundingBox.height
        )
        try container.encode(bb, forKey: .boundingBox)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(embedding, forKey: .embedding)
        try container.encode(qualityScore, forKey: .qualityScore)
    }
}

// MARK: - EmbeddingEntry

/// Embedding entry for index.
struct EmbeddingEntry: Codable, Equatable, Hashable, Sendable {
    let imageId: String
    let embedding: [Double]
    let qualityScore: Double
}

// MARK: - PersonIndexEntry

/// Index entry for quick loading (stored in index.json).
struct PersonIndexEntry: Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let imageCount: Int
    let thumbnailPath: String
    let embeddings: [EmbeddingEntry]

    /// Create from a full Person object.
    static func fromPerson(_ person: Person) -> PersonIndexEntry {
        PersonIndexEntry(
            id: person.id,
            name: person.name,
            imageCount: person.imageCount,
            thumbnailPath: person.thumbnailPath,
            embeddings: person.images.map { img in
                EmbeddingEntry(
                    imageId: img.id,
                    embedding: img.embedding,
                    qualityScore: img.qualityScore
                )
            }
        )
    }
}

// MARK: - PeopleIndex

/// People index file structure.
struct PeopleIndex: Codable, Equatable, Hashable, Sendable {
    let version: Int
    let lastModified: Date
    let people: [PersonIndexEntry]

    init(
        version: Int,
        lastModified: Date,
        people: [PersonIndexEntry]
    ) {
        self.version = version
        self.lastModified = lastModified
        self.people = people
    }

    /// Create empty index.
    static func empty() -> PeopleIndex {
        PeopleIndex(version: 1, lastModified: Date(), people: [])
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version, lastModified, people
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let dateStr = try container.decode(String.self, forKey: .lastModified)
        lastModified = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        people = try container.decode([PersonIndexEntry].self, forKey: .people)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(ISO8601DateFormatter().string(from: lastModified), forKey: .lastModified)
        try container.encode(people, forKey: .people)
    }
}

// MARK: - CodableBoundingBox (Helper)

/// Internal helper for encoding/decoding CGRect as {x, y, width, height} JSON.
struct CodableBoundingBox: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
