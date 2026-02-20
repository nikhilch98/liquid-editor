import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - PersonImage Tests

@Suite("PersonImage Tests")
struct PersonImageTests {

    private func makeImage(
        id: String = "img-1",
        imagePath: String = "/images/face1.jpg",
        embedding: [Double] = [0.1, 0.2, 0.3],
        qualityScore: Double = 0.85,
        addedAt: Date = Date(timeIntervalSince1970: 1000),
        boundingBox: CGRect? = nil
    ) -> PersonImage {
        PersonImage(
            id: id,
            imagePath: imagePath,
            embedding: embedding,
            qualityScore: qualityScore,
            addedAt: addedAt,
            boundingBox: boundingBox
        )
    }

    @Test("creation with all fields")
    func creation() {
        let img = makeImage(boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        #expect(img.id == "img-1")
        #expect(img.imagePath == "/images/face1.jpg")
        #expect(img.embedding == [0.1, 0.2, 0.3])
        #expect(img.qualityScore == 0.85)
        #expect(img.boundingBox != nil)
    }

    @Test("Equatable is by ID only")
    func equalityById() {
        let a = makeImage(id: "img-1", qualityScore: 0.5)
        let b = makeImage(id: "img-1", qualityScore: 0.9)
        #expect(a == b)
    }

    @Test("Hash is by ID only")
    func hashById() {
        let a = makeImage(id: "img-1", qualityScore: 0.5)
        let b = makeImage(id: "img-1", qualityScore: 0.9)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("with() copy method")
    func withCopy() {
        let img = makeImage()
        let modified = img.with(qualityScore: 0.95)
        #expect(modified.qualityScore == 0.95)
        #expect(modified.id == "img-1")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = makeImage(boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersonImage.self, from: data)
        #expect(decoded == original)
        #expect(decoded.embedding == [0.1, 0.2, 0.3])
        #expect(decoded.boundingBox != nil)
    }
}

// MARK: - Person Tests

@Suite("Person Tests")
struct PersonTests {

    private func makeImage(
        id: String = "img-1",
        qualityScore: Double = 0.85
    ) -> PersonImage {
        PersonImage(
            id: id,
            imagePath: "/images/\(id).jpg",
            embedding: [0.1, 0.2, 0.3],
            qualityScore: qualityScore,
            addedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    private func makePerson(
        id: String = "person-1",
        images: [PersonImage]? = nil
    ) -> Person {
        Person(
            id: id,
            name: "John",
            createdAt: Date(timeIntervalSince1970: 1000),
            modifiedAt: Date(timeIntervalSince1970: 2000),
            images: images ?? [makeImage()]
        )
    }

    @Test("creation with images")
    func creation() {
        let person = makePerson()
        #expect(person.id == "person-1")
        #expect(person.name == "John")
        #expect(person.imageCount == 1)
    }

    @Test("primaryEmbedding returns highest quality image embedding")
    func primaryEmbedding() {
        let lowQuality = makeImage(id: "img-low", qualityScore: 0.3)
        let highQuality = makeImage(id: "img-high", qualityScore: 0.9)
        let person = makePerson(images: [lowQuality, highQuality])
        #expect(person.primaryEmbedding != nil)
        #expect(person.primaryEmbedding == highQuality.embedding)
    }

    @Test("primaryEmbedding returns nil for no images")
    func primaryEmbeddingNoImages() {
        let person = makePerson(images: [])
        #expect(person.primaryEmbedding == nil)
    }

    @Test("allEmbeddings returns all")
    func allEmbeddings() {
        let img1 = makeImage(id: "img-1")
        let img2 = makeImage(id: "img-2")
        let person = makePerson(images: [img1, img2])
        #expect(person.allEmbeddings.count == 2)
    }

    @Test("thumbnailPath returns first image path")
    func thumbnailPath() {
        let person = makePerson()
        #expect(person.thumbnailPath == "/images/img-1.jpg")
    }

    @Test("thumbnailPath returns empty string for no images")
    func thumbnailPathEmpty() {
        let person = makePerson(images: [])
        #expect(person.thumbnailPath == "")
    }

    @Test("canAddMoreImages with fewer than 5")
    func canAddMoreImages() {
        let person = makePerson()
        #expect(person.canAddMoreImages == true)
    }

    @Test("canAddMoreImages with 5 images")
    func canAddMoreImagesFull() {
        let images = (0..<5).map { makeImage(id: "img-\($0)") }
        let person = makePerson(images: images)
        #expect(person.canAddMoreImages == false)
    }

    @Test("Equatable is by ID only")
    func equalityById() {
        let a = makePerson(id: "same")
        let b = Person(id: "same", name: "Different", createdAt: Date(), modifiedAt: Date(), images: [])
        #expect(a == b)
    }

    @Test("with() copy method")
    func withCopy() {
        let person = makePerson()
        let modified = person.with(name: "Jane")
        #expect(modified.name == "Jane")
        #expect(modified.id == person.id)
    }
}

// MARK: - DetectedPerson Tests

@Suite("DetectedPerson Tests")
struct DetectedPersonTests {

    @Test("qualityLabel for various scores")
    func qualityLabels() {
        let excellent = DetectedPerson(id: "1", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.9)
        #expect(excellent.qualityLabel == "Excellent")

        let great = DetectedPerson(id: "2", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.75)
        #expect(great.qualityLabel == "Great")

        let good = DetectedPerson(id: "3", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.55)
        #expect(good.qualityLabel == "Good")

        let fair = DetectedPerson(id: "4", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.35)
        #expect(fair.qualityLabel == "Fair")

        let poor = DetectedPerson(id: "5", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.1)
        #expect(poor.qualityLabel == "Poor")
    }

    @Test("qualityStars for various scores")
    func qualityStars() {
        let five = DetectedPerson(id: "1", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.9)
        #expect(five.qualityStars == 5)

        let one = DetectedPerson(id: "2", boundingBox: .zero, confidence: 0.9, embedding: [], qualityScore: 0.1)
        #expect(one.qualityStars == 1)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = DetectedPerson(
            id: "dp-1",
            boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            confidence: 0.95,
            embedding: [0.5, 0.6],
            qualityScore: 0.88
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DetectedPerson.self, from: data)
        #expect(decoded.id == "dp-1")
        #expect(decoded.confidence == 0.95)
        #expect(decoded.qualityScore == 0.88)
    }
}

// MARK: - PersonDetectionResult Tests

@Suite("PersonDetectionResult Tests")
struct PersonDetectionResultTests {

    @Test("success result")
    func successResult() {
        let result = PersonDetectionResult(success: true, personCount: 2)
        #expect(result.success == true)
        #expect(result.personCount == 2)
        #expect(result.errorMessage == nil)
        #expect(result.errorType == nil)
    }

    @Test("error result")
    func errorResult() {
        let result = PersonDetectionResult(
            success: false,
            errorMessage: "No face found",
            errorType: .noPersonDetected
        )
        #expect(result.success == false)
        #expect(result.errorMessage == "No face found")
        #expect(result.errorType == .noPersonDetected)
    }
}

// MARK: - PersonIndexEntry Tests

@Suite("PersonIndexEntry Tests")
struct PersonIndexEntryTests {

    @Test("fromPerson creates index entry")
    func fromPerson() {
        let img = PersonImage(
            id: "img-1", imagePath: "/face.jpg",
            embedding: [0.1, 0.2], qualityScore: 0.9,
            addedAt: Date(timeIntervalSince1970: 1000)
        )
        let person = Person(
            id: "p-1", name: "Alice",
            createdAt: Date(), modifiedAt: Date(),
            images: [img]
        )
        let entry = PersonIndexEntry.fromPerson(person)
        #expect(entry.id == "p-1")
        #expect(entry.name == "Alice")
        #expect(entry.imageCount == 1)
        #expect(entry.thumbnailPath == "/face.jpg")
        #expect(entry.embeddings.count == 1)
        #expect(entry.embeddings[0].imageId == "img-1")
    }
}

// MARK: - PersonDetectionError Tests

@Suite("PersonDetectionError Tests")
struct PersonDetectionErrorTests {

    @Test("all cases exist")
    func allCases() {
        #expect(PersonDetectionError.allCases.count == 6)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for error in PersonDetectionError.allCases {
            let data = try JSONEncoder().encode(error)
            let decoded = try JSONDecoder().decode(PersonDetectionError.self, from: data)
            #expect(decoded == error)
        }
    }
}
