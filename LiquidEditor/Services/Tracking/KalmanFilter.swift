//
//  KalmanFilter.swift
//  LiquidEditor
//
//  2D Kalman Filter for trajectory smoothing.
//  State vector: [x, y, vx, vy] (position + velocity).
//  Includes RTS backward smoother for optimal bidirectional estimates.
//
//

import CoreGraphics
import Foundation

// MARK: - Kalman Snapshot

/// Stores forward-pass filtered state for the RTS backward smoother.
struct KalmanSnapshot {
    let filteredState: [Double]
    let filteredCovariance: [[Double]]
    let adaptiveProcessNoise: Double
}

// MARK: - KalmanFilter2D

/// 2D Kalman Filter for smoothing tracking trajectories.
///
/// Thread Safety: `@unchecked Sendable` -- only called from
/// `TrackingDataStore` actor which provides serialized access.
final class KalmanFilter2D: @unchecked Sendable {

    // MARK: - State

    private var state: [Double]
    private var P: [[Double]]
    private let baseProcessNoise: Double
    private var adaptiveProcessNoise: Double
    private let measurementNoise: Double
    private var dt: Double
    private var isInitialized = false

    // MARK: - Initialization

    init(processNoise: Double = 0.01, measurementNoise: Double = 0.1, dt: Double = 1.0 / 30.0) {
        self.baseProcessNoise = processNoise
        self.adaptiveProcessNoise = processNoise
        self.measurementNoise = measurementNoise
        self.dt = dt
        self.state = [0, 0, 0, 0]
        self.P = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
    }

    // MARK: - Public Interface

    /// Update filter with new measurement.
    func update(measurement: CGPoint) -> CGPoint {
        let (result, _) = update(measurement: measurement, collectSnapshot: false)
        return result
    }

    /// Update filter with new measurement, optionally collecting a snapshot.
    func update(measurement: CGPoint, collectSnapshot: Bool) -> (CGPoint, KalmanSnapshot?) {
        if !isInitialized {
            state[0] = Double(measurement.x)
            state[1] = Double(measurement.y)
            state[2] = 0
            state[3] = 0
            isInitialized = true
            let snapshot = collectSnapshot ? KalmanSnapshot(
                filteredState: state,
                filteredCovariance: P,
                adaptiveProcessNoise: adaptiveProcessNoise
            ) : nil
            return (measurement, snapshot)
        }

        predict()
        correct(measurement: measurement)

        let snapshot = collectSnapshot ? KalmanSnapshot(
            filteredState: state,
            filteredCovariance: P,
            adaptiveProcessNoise: adaptiveProcessNoise
        ) : nil

        return (CGPoint(x: state[0], y: state[1]), snapshot)
    }

    /// Predict next position without measurement.
    @discardableResult
    func predict() -> CGPoint {
        let F = stateTransitionMatrix()
        state = matrixVectorMultiply(F, state)
        let Q = processNoiseMatrix()
        let Ft = transpose(F)
        let FP = matrixMultiply(F, P)
        let FPFt = matrixMultiply(FP, Ft)
        P = matrixAdd(FPFt, Q)
        return CGPoint(x: state[0], y: state[1])
    }

    /// Reset filter state.
    func reset() {
        state = [0, 0, 0, 0]
        P = [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ]
        isInitialized = false
        adaptiveProcessNoise = baseProcessNoise
    }

    /// Update time step.
    func setTimeStep(_ newDt: Double) {
        guard newDt > 0 else { return }
        dt = newDt
    }

    /// Predicted velocity.
    var velocity: CGPoint {
        CGPoint(x: state[2], y: state[3])
    }

    // MARK: - Adaptive Process Noise Constants

    private static let innovationThreshold: Double = 0.05
    private static let scaleMax: Double = 50.0
    private static let decayFactor: Double = 0.8

    // MARK: - Correction

    private func correct(measurement: CGPoint) {
        let H: [[Double]] = [[1, 0, 0, 0], [0, 1, 0, 0]]
        let z = [Double(measurement.x), Double(measurement.y)]
        let Hx = [state[0], state[1]]
        let y = [z[0] - Hx[0], z[1] - Hx[1]]

        // Adaptive process noise
        let innovationMagnitude = sqrt(y[0] * y[0] + y[1] * y[1])
        if innovationMagnitude > Self.innovationThreshold {
            let scale = min(Self.scaleMax, 1.0 + pow(innovationMagnitude / Self.innovationThreshold, 2))
            adaptiveProcessNoise = baseProcessNoise * scale
        } else {
            adaptiveProcessNoise = adaptiveProcessNoise * Self.decayFactor + baseProcessNoise * (1.0 - Self.decayFactor)
        }

        let R = measurementNoiseMatrix()
        let Ht = transpose(H)
        let HP = matrixMultiply(H, P)
        let HPHt = matrixMultiply(HP, Ht)
        let S = matrixAdd(HPHt, R)
        let PHt = matrixMultiply(P, Ht)
        let Sinv = inverse2x2(S)
        let K = matrixMultiply(PHt, Sinv)
        let Ky = matrixVectorMultiply(K, y)

        for i in 0..<4 {
            state[i] += Ky[i]
        }

        let KH = matrixMultiply(K, H)
        let I = Self.identity(4)
        let IminusKH = matrixSubtract(I, KH)
        P = matrixMultiply(IminusKH, P)
    }

    // MARK: - Matrix Operations (Instance)

    private func stateTransitionMatrix() -> [[Double]] { Self.stateTransitionMatrix(dt: dt) }
    private func processNoiseMatrix() -> [[Double]] { Self.processNoiseMatrix(q: adaptiveProcessNoise, dt: dt) }
    private func measurementNoiseMatrix() -> [[Double]] { [[measurementNoise, 0], [0, measurementNoise]] }

    private func transpose(_ m: [[Double]]) -> [[Double]] { Self.transpose(m) }
    private func matrixMultiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] { Self.matrixMultiply(a, b) }
    private func matrixVectorMultiply(_ m: [[Double]], _ v: [Double]) -> [Double] { Self.matrixVectorMultiply(m, v) }
    private func matrixAdd(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] { Self.matrixAdd(a, b) }
    private func matrixSubtract(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] { Self.matrixSubtract(a, b) }

    private func inverse2x2(_ m: [[Double]]) -> [[Double]] {
        let a = m[0][0], b = m[0][1], c = m[1][0], d = m[1][1]
        let det = a * d - b * c
        guard det != 0 else { return m }
        return [[d / det, -b / det], [-c / det, a / det]]
    }

    // MARK: - Static Matrix Operations

    static func stateTransitionMatrix(dt: Double) -> [[Double]] {
        [[1, 0, dt, 0], [0, 1, 0, dt], [0, 0, 1, 0], [0, 0, 0, 1]]
    }

    static func processNoiseMatrix(q: Double, dt: Double) -> [[Double]] {
        let dt2 = dt * dt
        let dt3 = dt2 * dt / 2
        let dt4 = dt2 * dt2 / 4
        return [
            [dt4 * q, 0, dt3 * q, 0],
            [0, dt4 * q, 0, dt3 * q],
            [dt3 * q, 0, dt2 * q, 0],
            [0, dt3 * q, 0, dt2 * q],
        ]
    }

    static func identity(_ n: Int) -> [[Double]] {
        var I = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n { I[i][i] = 1.0 }
        return I
    }

    static func transpose(_ m: [[Double]]) -> [[Double]] {
        guard !m.isEmpty else { return m }
        let rows = m.count, cols = m[0].count
        var result = Array(repeating: Array(repeating: 0.0, count: rows), count: cols)
        for i in 0..<rows { for j in 0..<cols { result[j][i] = m[i][j] } }
        return result
    }

    static func matrixMultiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        let rowsA = a.count, colsA = a[0].count, colsB = b[0].count
        var result = Array(repeating: Array(repeating: 0.0, count: colsB), count: rowsA)
        for i in 0..<rowsA { for j in 0..<colsB { for k in 0..<colsA { result[i][j] += a[i][k] * b[k][j] } } }
        return result
    }

    static func matrixVectorMultiply(_ m: [[Double]], _ v: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: m.count)
        for i in 0..<m.count { for j in 0..<v.count { result[i] += m[i][j] * v[j] } }
        return result
    }

    static func matrixAdd(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var result = a
        for i in 0..<a.count { for j in 0..<a[0].count { result[i][j] += b[i][j] } }
        return result
    }

    static func matrixSubtract(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var result = a
        for i in 0..<a.count { for j in 0..<a[0].count { result[i][j] -= b[i][j] } }
        return result
    }

    static func vectorAdd(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = a; for i in 0..<a.count { r[i] += b[i] }; return r
    }

    static func vectorSubtract(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = a; for i in 0..<a.count { r[i] -= b[i] }; return r
    }

    /// Analytical 4x4 matrix inverse.
    static func inverse4x4(_ m: [[Double]]) -> [[Double]] {
        let s0 = m[0][0] * m[1][1] - m[1][0] * m[0][1]
        let s1 = m[0][0] * m[1][2] - m[1][0] * m[0][2]
        let s2 = m[0][0] * m[1][3] - m[1][0] * m[0][3]
        let s3 = m[0][1] * m[1][2] - m[1][1] * m[0][2]
        let s4 = m[0][1] * m[1][3] - m[1][1] * m[0][3]
        let s5 = m[0][2] * m[1][3] - m[1][2] * m[0][3]
        let c5 = m[2][2] * m[3][3] - m[3][2] * m[2][3]
        let c4 = m[2][1] * m[3][3] - m[3][1] * m[2][3]
        let c3 = m[2][1] * m[3][2] - m[3][1] * m[2][2]
        let c2 = m[2][0] * m[3][3] - m[3][0] * m[2][3]
        let c1 = m[2][0] * m[3][2] - m[3][0] * m[2][2]
        let c0 = m[2][0] * m[3][1] - m[3][0] * m[2][1]
        let det = s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0
        guard abs(det) > 1e-15 else { return identity(4) }
        let inv = 1.0 / det
        return [
            [(m[1][1]*c5 - m[1][2]*c4 + m[1][3]*c3)*inv, (-m[0][1]*c5 + m[0][2]*c4 - m[0][3]*c3)*inv, (m[3][1]*s5 - m[3][2]*s4 + m[3][3]*s3)*inv, (-m[2][1]*s5 + m[2][2]*s4 - m[2][3]*s3)*inv],
            [(-m[1][0]*c5 + m[1][2]*c2 - m[1][3]*c1)*inv, (m[0][0]*c5 - m[0][2]*c2 + m[0][3]*c1)*inv, (-m[3][0]*s5 + m[3][2]*s2 - m[3][3]*s1)*inv, (m[2][0]*s5 - m[2][2]*s2 + m[2][3]*s1)*inv],
            [(m[1][0]*c4 - m[1][1]*c2 + m[1][3]*c0)*inv, (-m[0][0]*c4 + m[0][1]*c2 - m[0][3]*c0)*inv, (m[3][0]*s4 - m[3][1]*s2 + m[3][3]*s0)*inv, (-m[2][0]*s4 + m[2][1]*s2 - m[2][3]*s0)*inv],
            [(-m[1][0]*c3 + m[1][1]*c1 - m[1][2]*c0)*inv, (m[0][0]*c3 - m[0][1]*c1 + m[0][2]*c0)*inv, (-m[3][0]*s3 + m[3][1]*s1 - m[3][2]*s0)*inv, (m[2][0]*s3 - m[2][1]*s1 + m[2][2]*s0)*inv],
        ]
    }

    // MARK: - RTS Smoother

    /// Apply Rauch-Tung-Striebel backward smoother.
    static func rtsSmooth(snapshots: [KalmanSnapshot], dt: Double) -> [(x: Double, y: Double)] {
        let n = snapshots.count
        guard n > 1 else {
            if n == 1 { return [(snapshots[0].filteredState[0], snapshots[0].filteredState[1])] }
            return []
        }

        var smoothedStates: [[Double]] = Array(repeating: [0, 0, 0, 0], count: n)
        smoothedStates[n - 1] = snapshots[n - 1].filteredState

        let F = stateTransitionMatrix(dt: dt)
        let Ft = transpose(F)

        for k in stride(from: n - 2, through: 0, by: -1) {
            let xk = snapshots[k].filteredState
            let Pk = snapshots[k].filteredCovariance
            let qk = snapshots[k].adaptiveProcessNoise

            let xk1_pred = matrixVectorMultiply(F, xk)
            let Qk = processNoiseMatrix(q: qk, dt: dt)
            let FPk = matrixMultiply(F, Pk)
            let FPkFt = matrixMultiply(FPk, Ft)
            let Pk1_pred = matrixAdd(FPkFt, Qk)

            var Pk1_reg = Pk1_pred
            for i in 0..<4 { Pk1_reg[i][i] += 1e-10 }

            let PkFt = matrixMultiply(Pk, Ft)
            let Pk1_inv = inverse4x4(Pk1_reg)
            let G = matrixMultiply(PkFt, Pk1_inv)

            let diff = vectorSubtract(smoothedStates[k + 1], xk1_pred)
            let correction = matrixVectorMultiply(G, diff)
            smoothedStates[k] = vectorAdd(xk, correction)
        }

        return smoothedStates.map { ($0[0], $0[1]) }
    }
}
