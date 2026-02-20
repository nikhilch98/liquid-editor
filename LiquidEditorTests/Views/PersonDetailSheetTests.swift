import Testing
import Foundation
@testable import LiquidEditor

@Suite("PersonDetailSheet Tests")
struct PersonDetailSheetTests {

    // MARK: - Helper

    private static func makePerson(
        imageCount: Int = 2,
        name: String = "Test Person"
    ) -> Person {
        let images = (0..<imageCount).map { i in
            PersonImage(
                id: "img-\(i)",
                imagePath: "people/test/\(i).jpg",
                embedding: Array(repeating: 0.1, count: 128),
                qualityScore: Double(imageCount - i) / Double(imageCount),
                addedAt: Date()
            )
        }
        return Person(
            id: "person-1",
            name: name,
            createdAt: Date(),
            modifiedAt: Date(),
            images: images
        )
    }

    // MARK: - Quality Score to Stars

    @Suite("Quality to Stars Conversion")
    struct QualityToStarsTests {

        @Test("Score 0.0 maps to 1 star (minimum)")
        func zeroScore() {
            #expect(PersonDetailSheet.qualityToStars(0.0) == 1)
        }

        @Test("Score 1.0 maps to 5 stars (maximum)")
        func maxScore() {
            #expect(PersonDetailSheet.qualityToStars(1.0) == 5)
        }

        @Test("Score 0.5 maps to 3 stars")
        func midScore() {
            #expect(PersonDetailSheet.qualityToStars(0.5) == 3)
        }

        @Test("Score 0.2 maps to 1 star")
        func lowScore() {
            #expect(PersonDetailSheet.qualityToStars(0.2) == 1)
        }

        @Test("Score 0.8 maps to 4 stars")
        func highScore() {
            #expect(PersonDetailSheet.qualityToStars(0.8) == 4)
        }

        @Test("Score 0.99 maps to 5 stars")
        func nearMaxScore() {
            #expect(PersonDetailSheet.qualityToStars(0.99) == 5)
        }

        @Test("Negative score clamps to 1")
        func negativeScore() {
            #expect(PersonDetailSheet.qualityToStars(-0.5) >= 1)
        }

        @Test("Score above 1.0 clamps to 5")
        func overMaxScore() {
            #expect(PersonDetailSheet.qualityToStars(1.5) <= 5)
        }
    }

    // MARK: - Person Image Management

    @Suite("Image Management Logic")
    struct ImageManagementTests {

        @Test("Person with 2 images can add more")
        func canAddMore() {
            let person = makePerson(imageCount: 2)
            #expect(person.canAddMoreImages == true)
        }

        @Test("Person with 5 images cannot add more")
        func cannotAddMore() {
            let person = makePerson(imageCount: 5)
            #expect(person.canAddMoreImages == false)
        }

        @Test("Person with 0 images can add more")
        func emptyCanAddMore() {
            let person = makePerson(imageCount: 0)
            #expect(person.canAddMoreImages == true)
        }

        @Test("Removing an image reduces count")
        func removeReducesCount() {
            let person = makePerson(imageCount: 3)
            let updatedImages = Array(person.images.dropFirst())
            let updated = person.with(images: updatedImages)
            #expect(updated.imageCount == 2)
        }

        @Test("Person image count matches images array")
        func imageCountConsistent() {
            let person = makePerson(imageCount: 4)
            #expect(person.imageCount == person.images.count)
        }
    }

    // MARK: - Rename Logic

    @Suite("Rename Logic")
    struct RenameTests {

        @Test("Rename with new name updates person")
        func renameUpdates() {
            let person = makePerson(name: "Alice")
            let renamed = person.with(name: "Bob")
            #expect(renamed.name == "Bob")
            #expect(renamed.id == person.id)
        }

        @Test("Rename preserves other fields")
        func renamePreservesFields() {
            let person = makePerson(imageCount: 3, name: "Alice")
            let renamed = person.with(name: "Bob")
            #expect(renamed.imageCount == 3)
            #expect(renamed.createdAt == person.createdAt)
        }
    }

    // MARK: - PersonImage Model

    @Suite("PersonImage Model")
    struct PersonImageModelTests {

        @Test("PersonImage has unique ID")
        func uniqueId() {
            let img1 = PersonImage(
                id: "img-1",
                imagePath: "path/1.jpg",
                embedding: [],
                qualityScore: 0.8,
                addedAt: Date()
            )
            let img2 = PersonImage(
                id: "img-2",
                imagePath: "path/2.jpg",
                embedding: [],
                qualityScore: 0.7,
                addedAt: Date()
            )
            #expect(img1.id != img2.id)
        }

        @Test("PersonImage equality is by ID")
        func equalityById() {
            let date = Date()
            let img1 = PersonImage(
                id: "same-id",
                imagePath: "path/1.jpg",
                embedding: [0.1],
                qualityScore: 0.8,
                addedAt: date
            )
            let img2 = PersonImage(
                id: "same-id",
                imagePath: "path/different.jpg",
                embedding: [0.2],
                qualityScore: 0.5,
                addedAt: date
            )
            #expect(img1 == img2)
        }

        @Test("PersonImage inequality for different IDs")
        func inequalityDifferentIds() {
            let img1 = PersonImage(
                id: "id-a",
                imagePath: "path/1.jpg",
                embedding: [],
                qualityScore: 0.8,
                addedAt: Date()
            )
            let img2 = PersonImage(
                id: "id-b",
                imagePath: "path/1.jpg",
                embedding: [],
                qualityScore: 0.8,
                addedAt: Date()
            )
            #expect(img1 != img2)
        }
    }
}
