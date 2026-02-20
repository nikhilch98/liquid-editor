import Foundation

// MARK: - CurvePoint

/// A single control point on a curve.
struct CurvePoint: Codable, Equatable, Hashable, Sendable {
    /// Input value (0.0 to 1.0).
    let x: Double

    /// Output value (0.0 to 1.0).
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    // MARK: - Equatable (epsilon-based)

    private static let epsilon: Double = 0.0001

    static func == (lhs: CurvePoint, rhs: CurvePoint) -> Bool {
        abs(lhs.x - rhs.x) < epsilon
            && abs(lhs.y - rhs.y) < epsilon
    }

    // MARK: - Hashable (rounded for epsilon tolerance)

    func hash(into hasher: inout Hasher) {
        hasher.combine((x * 10000).rounded())
        hasher.combine((y * 10000).rounded())
    }
}

// MARK: - CurveData

/// Curve data with control points and evaluation.
///
/// Always starts at (0,0) and ends at (1,1) for identity.
/// Minimum 2 points, maximum 16 points.
/// Uses monotone cubic Hermite interpolation (Fritsch-Carlson) to
/// prevent ringing/overshoot artifacts.
struct CurveData: Codable, Equatable, Hashable, Sendable {
    /// Control points sorted by x.
    let points: [CurvePoint]

    init(points: [CurvePoint]) {
        self.points = points
    }

    /// Identity curve (straight diagonal).
    static let identity = CurveData(points: [
        CurvePoint(0.0, 0.0),
        CurvePoint(1.0, 1.0),
    ])

    /// Whether this is an identity curve.
    var isIdentity: Bool {
        points.count == 2
            && abs(points[0].x - 0.0) < 0.0001
            && abs(points[0].y - 0.0) < 0.0001
            && abs(points[1].x - 1.0) < 0.0001
            && abs(points[1].y - 1.0) < 0.0001
    }

    /// Number of control points.
    var pointCount: Int { points.count }

    /// Whether a new point can be added.
    var canAddPoint: Bool { points.count < 16 }

    /// Add a control point, maintaining sort order.
    /// Returns nil if at maximum (16 points).
    func addPoint(_ point: CurvePoint) -> CurveData? {
        guard canAddPoint else { return nil }
        var newPoints = points
        newPoints.append(point)
        newPoints.sort { $0.x < $1.x }
        return CurveData(points: newPoints)
    }

    /// Remove a control point by index.
    /// Cannot remove endpoints (index 0 and last).
    func removePointAt(_ index: Int) -> CurveData? {
        guard index > 0, index < points.count - 1, points.count > 2 else { return nil }
        var newPoints = points
        newPoints.remove(at: index)
        return CurveData(points: newPoints)
    }

    /// Move a control point to a new position.
    /// X is constrained between neighboring points.
    /// Y is clamped to [0.0, 1.0].
    func movePoint(_ index: Int, newX: Double, newY: Double) -> CurveData {
        guard index >= 0, index < points.count else { return self }

        let clampedY = min(max(newY, 0.0), 1.0)

        let clampedX: Double
        if index == 0 {
            clampedX = 0.0
        } else if index == points.count - 1 {
            clampedX = 1.0
        } else {
            let minX = points[index - 1].x + 0.001
            let maxX = points[index + 1].x - 0.001
            clampedX = min(max(newX, minX), maxX)
        }

        var newPoints = points
        newPoints[index] = CurvePoint(clampedX, clampedY)
        return CurveData(points: newPoints)
    }

    /// Evaluate the curve at a given input value using monotone cubic
    /// Hermite interpolation (Fritsch-Carlson method).
    func evaluate(_ input: Double) -> Double {
        guard !points.isEmpty else { return input }
        guard points.count > 1 else { return points[0].y }

        let x = min(max(input, 0.0), 1.0)

        if x <= points.first!.x { return points.first!.y }
        if x >= points.last!.x { return points.last!.y }

        // Binary search for the interval
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if points[mid].x <= x {
                low = mid
            } else {
                high = mid
            }
        }

        if points.count == 2 {
            // Linear interpolation for 2 points
            let t = (x - points[low].x) / (points[high].x - points[low].x)
            return points[low].y + t * (points[high].y - points[low].y)
        }

        return evaluateMonotoneCubic(x, i: low)
    }

    private func evaluateMonotoneCubic(_ x: Double, i: Int) -> Double {
        let n = points.count

        // Compute slopes (deltas)
        var deltas: [Double] = []
        for k in 0..<(n - 1) {
            let dx = points[k + 1].x - points[k].x
            if abs(dx) < 1e-10 {
                deltas.append(0.0)
            } else {
                deltas.append((points[k + 1].y - points[k].y) / dx)
            }
        }

        // Compute tangents using Fritsch-Carlson method
        var tangents = [Double](repeating: 0.0, count: n)

        // Endpoints
        tangents[0] = deltas[0]
        tangents[n - 1] = deltas[n - 2]

        // Interior points
        for k in 1..<(n - 1) {
            if deltas[k - 1].sign != deltas[k].sign
                || abs(deltas[k - 1]) < 1e-10
                || abs(deltas[k]) < 1e-10
            {
                tangents[k] = 0.0
            } else {
                tangents[k] = (deltas[k - 1] + deltas[k]) / 2.0
            }
        }

        // Enforce monotonicity (Fritsch-Carlson conditions)
        for k in 0..<(n - 1) {
            if abs(deltas[k]) < 1e-10 {
                tangents[k] = 0.0
                tangents[k + 1] = 0.0
            } else {
                let alpha = tangents[k] / deltas[k]
                let beta = tangents[k + 1] / deltas[k]
                let sum = alpha * alpha + beta * beta
                if sum > 9.0 {
                    let tau = 3.0 / sum.squareRoot()
                    tangents[k] = tau * alpha * deltas[k]
                    tangents[k + 1] = tau * beta * deltas[k]
                }
            }
        }

        // Evaluate cubic Hermite basis
        let h = points[i + 1].x - points[i].x
        guard abs(h) >= 1e-10 else { return points[i].y }

        let t = (x - points[i].x) / h
        let t2 = t * t
        let t3 = t2 * t

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        let result = h00 * points[i].y
            + h10 * h * tangents[i]
            + h01 * points[i + 1].y
            + h11 * h * tangents[i + 1]

        return min(max(result, 0.0), 1.0)
    }

    /// Sample the curve at `sampleCount` evenly-spaced points.
    /// Returns a list of output values.
    func sample(_ sampleCount: Int) -> [Double] {
        (0..<sampleCount).map { i in
            let x = Double(i) / Double(sampleCount - 1)
            return evaluate(x)
        }
    }

    /// Linearly interpolate between two curves by sampling.
    static func lerp(_ a: CurveData, _ b: CurveData, t: Double) -> CurveData {
        if t <= 0.0 { return a }
        if t >= 1.0 { return b }

        if a.isIdentity && b.isIdentity { return .identity }

        // If both have matching point count, interpolate per-point
        if a.points.count == b.points.count {
            let newPoints = zip(a.points, b.points).map { pa, pb in
                CurvePoint(
                    pa.x + (pb.x - pa.x) * t,
                    pa.y + (pb.y - pa.y) * t
                )
            }
            return CurveData(points: newPoints)
        }

        // Different point counts: sample at 17 points and interpolate
        let sampleCount = 17
        let samplesA = a.sample(sampleCount)
        let samplesB = b.sample(sampleCount)

        let newPoints = (0..<sampleCount).map { i in
            let x = Double(i) / Double(sampleCount - 1)
            let y = samplesA[i] + (samplesB[i] - samplesA[i]) * t
            return CurvePoint(x, y)
        }

        return CurveData(points: newPoints)
    }
}
