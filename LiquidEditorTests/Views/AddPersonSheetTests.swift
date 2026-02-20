import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("AddPersonSheet Tests")
struct AddPersonSheetTests {

    // MARK: - AddPersonState Enum

    @Suite("AddPersonState")
    struct AddPersonStateTests {

        @Test("All cases exist")
        func allCases() {
            let cases = AddPersonState.allCases
            #expect(cases.count == 8)
            #expect(cases.contains(.initial))
            #expect(cases.contains(.pickingImage))
            #expect(cases.contains(.detecting))
            #expect(cases.contains(.selectingPerson))
            #expect(cases.contains(.enteringName))
            #expect(cases.contains(.checkingDuplicate))
            #expect(cases.contains(.saving))
            #expect(cases.contains(.error))
        }

        @Test("Raw values are correct strings")
        func rawValues() {
            #expect(AddPersonState.initial.rawValue == "initial")
            #expect(AddPersonState.pickingImage.rawValue == "pickingImage")
            #expect(AddPersonState.detecting.rawValue == "detecting")
            #expect(AddPersonState.selectingPerson.rawValue == "selectingPerson")
            #expect(AddPersonState.enteringName.rawValue == "enteringName")
            #expect(AddPersonState.checkingDuplicate.rawValue == "checkingDuplicate")
            #expect(AddPersonState.saving.rawValue == "saving")
            #expect(AddPersonState.error.rawValue == "error")
        }
    }

    // MARK: - Person Model Validation

    @Suite("Person Model for AddPersonSheet")
    struct PersonModelTests {

        @Test("Person created with valid name")
        func validName() {
            let person = Person(
                id: "test-1",
                name: "John Doe",
                createdAt: Date(),
                modifiedAt: Date(),
                images: []
            )
            #expect(person.name == "John Doe")
        }

        @Test("Person created with empty images starts with count 0")
        func emptyImages() {
            let person = Person(
                id: "test-1",
                name: "Jane",
                createdAt: Date(),
                modifiedAt: Date(),
                images: []
            )
            #expect(person.imageCount == 0)
            #expect(person.canAddMoreImages == true)
        }

        @Test("Person with 5 images cannot add more")
        func maxImages() {
            let images = (0..<5).map { i in
                PersonImage(
                    id: "img-\(i)",
                    imagePath: "path/\(i).jpg",
                    embedding: [],
                    qualityScore: 0.8,
                    addedAt: Date()
                )
            }
            let person = Person(
                id: "test-1",
                name: "Jane",
                createdAt: Date(),
                modifiedAt: Date(),
                images: images
            )
            #expect(person.imageCount == 5)
            #expect(person.canAddMoreImages == false)
        }
    }

    // MARK: - DetectedPerson Quality

    @Suite("DetectedPerson Quality Assessment")
    struct DetectedPersonQualityTests {

        @Test("Quality score >= 0.85 is Excellent")
        func qualityExcellent() {
            let person = DetectedPerson(
                id: "p1",
                boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                confidence: 0.95,
                embedding: [],
                qualityScore: 0.90
            )
            #expect(person.qualityLabel == "Excellent")
            #expect(person.qualityStars == 5)
        }

        @Test("Quality score >= 0.70 is Great")
        func qualityGreat() {
            let person = DetectedPerson(
                id: "p1",
                boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                confidence: 0.90,
                embedding: [],
                qualityScore: 0.75
            )
            #expect(person.qualityLabel == "Great")
            #expect(person.qualityStars == 4)
        }

        @Test("Quality score >= 0.50 is Good")
        func qualityGood() {
            let person = DetectedPerson(
                id: "p1",
                boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                confidence: 0.80,
                embedding: [],
                qualityScore: 0.55
            )
            #expect(person.qualityLabel == "Good")
            #expect(person.qualityStars == 3)
        }

        @Test("Quality score >= 0.30 is Fair")
        func qualityFair() {
            let person = DetectedPerson(
                id: "p1",
                boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                confidence: 0.70,
                embedding: [],
                qualityScore: 0.35
            )
            #expect(person.qualityLabel == "Fair")
            #expect(person.qualityStars == 2)
        }

        @Test("Quality score < 0.30 is Poor")
        func qualityPoor() {
            let person = DetectedPerson(
                id: "p1",
                boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
                confidence: 0.50,
                embedding: [],
                qualityScore: 0.10
            )
            #expect(person.qualityLabel == "Poor")
            #expect(person.qualityStars == 1)
        }
    }

    // MARK: - PersonDetectionResult

    @Suite("PersonDetectionResult")
    struct PersonDetectionResultTests {

        @Test("Success result with people")
        func successWithPeople() {
            let person = DetectedPerson(
                id: "p1",
                boundingBox: CGRect(x: 10, y: 20, width: 100, height: 150),
                confidence: 0.95,
                embedding: [0.1, 0.2, 0.3],
                qualityScore: 0.85
            )
            let result = PersonDetectionResult(
                success: true,
                personCount: 1,
                people: [person]
            )
            #expect(result.success == true)
            #expect(result.personCount == 1)
            #expect(result.people.count == 1)
            #expect(result.errorMessage == nil)
        }

        @Test("Failure result with error")
        func failureWithError() {
            let result = PersonDetectionResult(
                success: false,
                errorMessage: "No face found",
                errorType: .noPersonDetected
            )
            #expect(result.success == false)
            #expect(result.personCount == 0)
            #expect(result.people.isEmpty)
            #expect(result.errorMessage == "No face found")
            #expect(result.errorType == .noPersonDetected)
        }
    }
}
