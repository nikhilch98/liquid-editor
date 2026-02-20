import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - KalmanSnapshot Tests

@Suite("KalmanSnapshot Tests")
struct KalmanSnapshotTests {

    @Test("creation stores values")
    func creation() {
        let snapshot = KalmanSnapshot(
            filteredState: [1.0, 2.0, 0.1, 0.2],
            filteredCovariance: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
            adaptiveProcessNoise: 0.05
        )
        #expect(snapshot.filteredState == [1.0, 2.0, 0.1, 0.2])
        #expect(snapshot.adaptiveProcessNoise == 0.05)
        #expect(snapshot.filteredCovariance.count == 4)
    }
}

// MARK: - KalmanFilter2D Tests

@Suite("KalmanFilter2D Tests")
struct KalmanFilter2DTests {

    // MARK: - Initial State

    @Test("initial velocity is zero")
    func initialVelocity() {
        let filter = KalmanFilter2D()
        #expect(filter.velocity == CGPoint.zero)
    }

    // MARK: - First Update

    @Test("first update returns measurement exactly")
    func firstUpdateReturnsMeasurement() {
        let filter = KalmanFilter2D()
        let measurement = CGPoint(x: 0.5, y: 0.3)
        let result = filter.update(measurement: measurement)
        #expect(result.x == measurement.x)
        #expect(result.y == measurement.y)
    }

    @Test("first update with snapshot collection")
    func firstUpdateWithSnapshot() {
        let filter = KalmanFilter2D()
        let measurement = CGPoint(x: 0.5, y: 0.3)
        let (result, snapshot) = filter.update(measurement: measurement, collectSnapshot: true)
        #expect(result == measurement)
        #expect(snapshot != nil)
        #expect(snapshot!.filteredState[0] == 0.5)
        #expect(snapshot!.filteredState[1] == 0.3)
        #expect(snapshot!.filteredState[2] == 0) // velocity x
        #expect(snapshot!.filteredState[3] == 0) // velocity y
    }

    @Test("first update without snapshot returns nil")
    func firstUpdateWithoutSnapshot() {
        let filter = KalmanFilter2D()
        let (_, snapshot) = filter.update(measurement: CGPoint(x: 0.5, y: 0.3), collectSnapshot: false)
        #expect(snapshot == nil)
    }

    // MARK: - Convergence

    @Test("converges toward constant measurement")
    func convergesToConstant() {
        let filter = KalmanFilter2D()
        let target = CGPoint(x: 0.5, y: 0.5)

        var lastResult = CGPoint.zero
        for _ in 0..<20 {
            lastResult = filter.update(measurement: target)
        }

        #expect(abs(lastResult.x - target.x) < 0.01)
        #expect(abs(lastResult.y - target.y) < 0.01)
    }

    @Test("smooths noisy measurements")
    func smoothsNoisyData() {
        let filter = KalmanFilter2D()
        let baseX = 0.5
        let baseY = 0.5

        var results: [CGPoint] = []
        for i in 0..<30 {
            let noise = Double(i % 2 == 0 ? 1 : -1) * 0.05
            let measurement = CGPoint(x: baseX + noise, y: baseY + noise)
            let result = filter.update(measurement: measurement)
            results.append(result)
        }

        // Later results should be closer to the mean than the noisy inputs
        let lastResult = results.last!
        #expect(abs(lastResult.x - baseX) < 0.05)
        #expect(abs(lastResult.y - baseY) < 0.05)
    }

    // MARK: - Predict

    @Test("predict moves state forward using velocity")
    func predictMovesState() {
        let filter = KalmanFilter2D()

        // Feed a moving point to establish velocity
        _ = filter.update(measurement: CGPoint(x: 0.0, y: 0.0))
        _ = filter.update(measurement: CGPoint(x: 0.1, y: 0.1))
        _ = filter.update(measurement: CGPoint(x: 0.2, y: 0.2))

        let velocity = filter.velocity
        // After feeding a moving point, velocity should be positive
        #expect(velocity.x > 0)
        #expect(velocity.y > 0)

        let predicted = filter.predict()
        // Predicted position should be further along the trajectory (Kalman gain dampens predictions)
        #expect(predicted.x > 0.1)
        #expect(predicted.y > 0.1)
    }

    // MARK: - Reset

    @Test("reset clears state to initial")
    func resetClearsState() {
        let filter = KalmanFilter2D()
        _ = filter.update(measurement: CGPoint(x: 0.5, y: 0.5))
        _ = filter.update(measurement: CGPoint(x: 0.6, y: 0.6))

        filter.reset()

        #expect(filter.velocity == CGPoint.zero)

        // After reset, next update should return measurement exactly (first update behavior)
        let result = filter.update(measurement: CGPoint(x: 0.1, y: 0.1))
        #expect(result.x == 0.1)
        #expect(result.y == 0.1)
    }

    // MARK: - setTimeStep

    @Test("setTimeStep ignores non-positive values")
    func setTimeStepIgnoresNonPositive() {
        let filter = KalmanFilter2D()
        _ = filter.update(measurement: CGPoint(x: 0.5, y: 0.5))

        filter.setTimeStep(0)
        filter.setTimeStep(-1)

        // Filter should still work correctly
        let result = filter.update(measurement: CGPoint(x: 0.6, y: 0.6))
        #expect(result.x > 0)
    }

    @Test("setTimeStep accepts positive values")
    func setTimeStepAcceptsPositive() {
        let filter = KalmanFilter2D()
        filter.setTimeStep(1.0 / 60.0) // 60fps

        let result = filter.update(measurement: CGPoint(x: 0.5, y: 0.5))
        #expect(result.x == 0.5) // First update still returns measurement exactly
    }

    // MARK: - Snapshot Collection

    @Test("subsequent updates collect snapshots")
    func subsequentSnapshotCollection() {
        let filter = KalmanFilter2D()
        _ = filter.update(measurement: CGPoint(x: 0.1, y: 0.1))
        let (result, snapshot) = filter.update(measurement: CGPoint(x: 0.2, y: 0.2), collectSnapshot: true)
        #expect(snapshot != nil)
        #expect(snapshot!.filteredState.count == 4)
        #expect(result.x > 0)
    }

    // MARK: - Static Matrix Operations

    @Test("identity matrix")
    func identityMatrix() {
        let I = KalmanFilter2D.identity(3)
        #expect(I.count == 3)
        for i in 0..<3 {
            for j in 0..<3 {
                #expect(I[i][j] == (i == j ? 1.0 : 0.0))
            }
        }
    }

    @Test("transpose matrix")
    func transposeMatrix() {
        let m: [[Double]] = [[1, 2, 3], [4, 5, 6]]
        let t = KalmanFilter2D.transpose(m)
        #expect(t.count == 3)
        #expect(t[0].count == 2)
        #expect(t[0][0] == 1)
        #expect(t[0][1] == 4)
        #expect(t[1][0] == 2)
        #expect(t[2][1] == 6)
    }

    @Test("transpose empty matrix")
    func transposeEmpty() {
        let t = KalmanFilter2D.transpose([])
        #expect(t.isEmpty)
    }

    @Test("matrix multiply")
    func matrixMultiply() {
        let a: [[Double]] = [[1, 2], [3, 4]]
        let b: [[Double]] = [[5, 6], [7, 8]]
        let result = KalmanFilter2D.matrixMultiply(a, b)
        #expect(result[0][0] == 19) // 1*5 + 2*7
        #expect(result[0][1] == 22) // 1*6 + 2*8
        #expect(result[1][0] == 43) // 3*5 + 4*7
        #expect(result[1][1] == 50) // 3*6 + 4*8
    }

    @Test("matrix vector multiply")
    func matrixVectorMultiply() {
        let m: [[Double]] = [[1, 2], [3, 4]]
        let v: [Double] = [5, 6]
        let result = KalmanFilter2D.matrixVectorMultiply(m, v)
        #expect(result[0] == 17) // 1*5 + 2*6
        #expect(result[1] == 39) // 3*5 + 4*6
    }

    @Test("matrix add")
    func matrixAdd() {
        let a: [[Double]] = [[1, 2], [3, 4]]
        let b: [[Double]] = [[5, 6], [7, 8]]
        let result = KalmanFilter2D.matrixAdd(a, b)
        #expect(result[0][0] == 6)
        #expect(result[1][1] == 12)
    }

    @Test("matrix subtract")
    func matrixSubtract() {
        let a: [[Double]] = [[5, 6], [7, 8]]
        let b: [[Double]] = [[1, 2], [3, 4]]
        let result = KalmanFilter2D.matrixSubtract(a, b)
        #expect(result[0][0] == 4)
        #expect(result[1][1] == 4)
    }

    @Test("vector add")
    func vectorAdd() {
        let result = KalmanFilter2D.vectorAdd([1, 2, 3], [4, 5, 6])
        #expect(result == [5, 7, 9])
    }

    @Test("vector subtract")
    func vectorSubtract() {
        let result = KalmanFilter2D.vectorSubtract([5, 7, 9], [4, 5, 6])
        #expect(result == [1, 2, 3])
    }

    @Test("state transition matrix structure")
    func stateTransitionMatrix() {
        let dt = 0.033
        let F = KalmanFilter2D.stateTransitionMatrix(dt: dt)
        #expect(F.count == 4)
        #expect(F[0][0] == 1)
        #expect(F[0][2] == dt)
        #expect(F[1][1] == 1)
        #expect(F[1][3] == dt)
        #expect(F[2][2] == 1)
        #expect(F[3][3] == 1)
    }

    @Test("process noise matrix is symmetric")
    func processNoiseSymmetric() {
        let Q = KalmanFilter2D.processNoiseMatrix(q: 0.01, dt: 0.033)
        #expect(Q.count == 4)
        // Check symmetry
        for i in 0..<4 {
            for j in 0..<4 {
                #expect(abs(Q[i][j] - Q[j][i]) < 1e-10)
            }
        }
    }

    // MARK: - inverse4x4

    @Test("inverse4x4 of identity is identity")
    func inverse4x4Identity() {
        let I = KalmanFilter2D.identity(4)
        let inv = KalmanFilter2D.inverse4x4(I)
        for i in 0..<4 {
            for j in 0..<4 {
                let expected = i == j ? 1.0 : 0.0
                #expect(abs(inv[i][j] - expected) < 1e-10)
            }
        }
    }

    @Test("inverse4x4 * original = identity")
    func inverse4x4Product() {
        let m: [[Double]] = [
            [2, 1, 0, 0],
            [1, 3, 1, 0],
            [0, 1, 4, 1],
            [0, 0, 1, 5],
        ]
        let inv = KalmanFilter2D.inverse4x4(m)
        let product = KalmanFilter2D.matrixMultiply(m, inv)
        for i in 0..<4 {
            for j in 0..<4 {
                let expected = i == j ? 1.0 : 0.0
                #expect(abs(product[i][j] - expected) < 1e-8)
            }
        }
    }

    @Test("inverse4x4 singular matrix returns identity")
    func inverse4x4Singular() {
        let singular: [[Double]] = [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ]
        let inv = KalmanFilter2D.inverse4x4(singular)
        // Should return identity for singular matrix
        for i in 0..<4 {
            #expect(inv[i][i] == 1.0)
        }
    }

    // MARK: - RTS Smoother

    @Test("rtsSmooth with empty returns empty")
    func rtsSmoothEmpty() {
        let result = KalmanFilter2D.rtsSmooth(snapshots: [], dt: 0.033)
        #expect(result.isEmpty)
    }

    @Test("rtsSmooth with single snapshot returns its position")
    func rtsSmoothSingle() {
        let snapshot = KalmanSnapshot(
            filteredState: [0.5, 0.3, 0.0, 0.0],
            filteredCovariance: KalmanFilter2D.identity(4),
            adaptiveProcessNoise: 0.01
        )
        let result = KalmanFilter2D.rtsSmooth(snapshots: [snapshot], dt: 0.033)
        #expect(result.count == 1)
        #expect(result[0].x == 0.5)
        #expect(result[0].y == 0.3)
    }

    @Test("rtsSmooth with multiple snapshots returns smoothed positions")
    func rtsSmoothMultiple() {
        let filter = KalmanFilter2D(processNoise: 0.01, measurementNoise: 0.1, dt: 0.033)
        var snapshots: [KalmanSnapshot] = []

        // Collect snapshots from a noisy linear trajectory
        for i in 0..<10 {
            let x = Double(i) * 0.1
            let noise = (i % 2 == 0 ? 1.0 : -1.0) * 0.02
            let measurement = CGPoint(x: x + noise, y: 0.5 + noise)
            let (_, snapshot) = filter.update(measurement: measurement, collectSnapshot: true)
            if let s = snapshot {
                snapshots.append(s)
            }
        }

        let smoothed = KalmanFilter2D.rtsSmooth(snapshots: snapshots, dt: 0.033)
        #expect(smoothed.count == snapshots.count)

        // All positions should be within a reasonable range
        for pos in smoothed {
            #expect(pos.x >= -0.5 && pos.x <= 1.5)
            #expect(pos.y >= -0.5 && pos.y <= 1.5)
        }
    }
}
