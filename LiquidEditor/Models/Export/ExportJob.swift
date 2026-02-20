// ExportJob.swift
// LiquidEditor
//
// Export job model representing an individual export task.

import Foundation

// MARK: - ExportJobStatus

/// State of an export job.
enum ExportJobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case preparing
    case rendering
    case encoding
    case saving
    case completed
    case failed
    case cancelled
    case paused
}

// MARK: - ExportJobPriority

/// Priority level for queue ordering.
enum ExportJobPriority: String, Codable, CaseIterable, Sendable {
    case high
    case normal
    case low
}

// MARK: - ExportProgress

/// Detailed progress information for an export operation.
struct ExportProgress: Codable, Equatable, Sendable {

    /// Unique identifier of the export this progress belongs to.
    let exportId: String

    /// Current phase of the export.
    let phase: ExportPhase

    /// Overall progress from 0.0 to 1.0.
    let overallProgress: Double

    /// Number of frames rendered so far.
    let framesRendered: Int

    /// Total number of frames to render.
    let totalFrames: Int

    /// Bytes written to output so far.
    let bytesWritten: Int

    /// Estimated total output size in bytes.
    let estimatedTotalBytes: Int

    /// When the export started.
    let startedAt: Date

    /// Time elapsed since export started (in milliseconds for serialization).
    let elapsedMs: Int

    /// Estimated time remaining in milliseconds (nil if unknown).
    let estimatedRemainingMs: Int?

    /// Device thermal state (0=nominal, 1=fair, 2=serious, 3=critical).
    let thermalState: Int?

    /// Available disk space in megabytes.
    let availableDiskMB: Int?

    // MARK: - Init with defaults

    init(
        exportId: String,
        phase: ExportPhase,
        overallProgress: Double,
        framesRendered: Int = 0,
        totalFrames: Int = 0,
        bytesWritten: Int = 0,
        estimatedTotalBytes: Int = 0,
        startedAt: Date,
        elapsedMs: Int,
        estimatedRemainingMs: Int? = nil,
        thermalState: Int? = nil,
        availableDiskMB: Int? = nil
    ) {
        self.exportId = exportId
        self.phase = phase
        self.overallProgress = overallProgress
        self.framesRendered = framesRendered
        self.totalFrames = totalFrames
        self.bytesWritten = bytesWritten
        self.estimatedTotalBytes = estimatedTotalBytes
        self.startedAt = startedAt
        self.elapsedMs = elapsedMs
        self.estimatedRemainingMs = estimatedRemainingMs
        self.thermalState = thermalState
        self.availableDiskMB = availableDiskMB
    }

    /// Time elapsed as TimeInterval.
    var elapsed: TimeInterval {
        Double(elapsedMs) / 1000.0
    }

    /// Estimated time remaining as TimeInterval (nil if unknown).
    var estimatedRemaining: TimeInterval? {
        estimatedRemainingMs.map { Double($0) / 1000.0 }
    }

    /// Human-readable ETA string.
    var etaString: String {
        guard let remainingMs = estimatedRemainingMs else { return "Calculating..." }
        let seconds = remainingMs / 1000
        if seconds < 60 { return "\(seconds)s remaining" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes)m \(remainingSeconds)s remaining"
    }

    /// Human-readable file size progress.
    var fileSizeString: String {
        guard estimatedTotalBytes > 0 else { return "" }
        let mb = Double(bytesWritten) / (1024.0 * 1024.0)
        let totalMb = Double(estimatedTotalBytes) / (1024.0 * 1024.0)
        if totalMb >= 1024 {
            return String(format: "%.1f / %.1f GB", mb / 1024.0, totalMb / 1024.0)
        }
        return String(format: "%.0f / %.0f MB", mb, totalMb)
    }

    /// Human-readable percentage.
    var percentageString: String {
        "\(Int(overallProgress * 100))%"
    }

    /// Whether thermal state requires attention.
    var isThermalConcern: Bool { (thermalState ?? 0) >= 2 }

    /// Whether disk space is low.
    var isDiskLow: Bool { (availableDiskMB ?? 10000) < 500 }

    /// Deserialize from a platform channel dictionary.
    static func fromMap(_ map: [String: Any]) -> ExportProgress {
        let elapsedMs = map["elapsedMs"] as? Int ?? 0
        let estimatedRemainingMs = map["estimatedRemainingMs"] as? Int

        let phaseStr = map["phase"] as? String ?? "rendering"
        let phase = ExportPhase(rawValue: phaseStr) ?? .rendering

        return ExportProgress(
            exportId: map["exportId"] as? String ?? "",
            phase: phase,
            overallProgress: (map["progress"] as? Double) ?? 0.0,
            framesRendered: map["framesRendered"] as? Int ?? 0,
            totalFrames: map["totalFrames"] as? Int ?? 0,
            bytesWritten: map["bytesWritten"] as? Int ?? 0,
            estimatedTotalBytes: map["estimatedTotalBytes"] as? Int ?? 0,
            startedAt: Date().addingTimeInterval(-Double(elapsedMs) / 1000.0),
            elapsedMs: elapsedMs,
            estimatedRemainingMs: estimatedRemainingMs,
            thermalState: map["thermalState"] as? Int,
            availableDiskMB: map["availableDiskMB"] as? Int
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case exportId
        case phase
        case overallProgress
        case framesRendered
        case totalFrames
        case bytesWritten
        case estimatedTotalBytes
        case elapsedMs
        case estimatedRemainingMs
        case thermalState
        case availableDiskMB
    }

    // MARK: - Custom Decoding (startedAt is computed, not serialized)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportId = try container.decode(String.self, forKey: .exportId)

        let phaseStr = try container.decode(String.self, forKey: .phase)
        phase = ExportPhase(rawValue: phaseStr) ?? .rendering

        overallProgress = try container.decodeIfPresent(Double.self, forKey: .overallProgress) ?? 0.0
        framesRendered = try container.decodeIfPresent(Int.self, forKey: .framesRendered) ?? 0
        totalFrames = try container.decodeIfPresent(Int.self, forKey: .totalFrames) ?? 0
        bytesWritten = try container.decodeIfPresent(Int.self, forKey: .bytesWritten) ?? 0
        estimatedTotalBytes = try container.decodeIfPresent(Int.self, forKey: .estimatedTotalBytes) ?? 0
        elapsedMs = try container.decodeIfPresent(Int.self, forKey: .elapsedMs) ?? 0
        startedAt = Date().addingTimeInterval(-Double(elapsedMs) / 1000.0)
        estimatedRemainingMs = try container.decodeIfPresent(Int.self, forKey: .estimatedRemainingMs)
        thermalState = try container.decodeIfPresent(Int.self, forKey: .thermalState)
        availableDiskMB = try container.decodeIfPresent(Int.self, forKey: .availableDiskMB)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportId, forKey: .exportId)
        try container.encode(phase.rawValue, forKey: .phase)
        try container.encode(overallProgress, forKey: .overallProgress)
        try container.encode(framesRendered, forKey: .framesRendered)
        try container.encode(totalFrames, forKey: .totalFrames)
        try container.encode(bytesWritten, forKey: .bytesWritten)
        try container.encode(estimatedTotalBytes, forKey: .estimatedTotalBytes)
        try container.encode(elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(estimatedRemainingMs, forKey: .estimatedRemainingMs)
        try container.encodeIfPresent(thermalState, forKey: .thermalState)
        try container.encodeIfPresent(availableDiskMB, forKey: .availableDiskMB)
    }
}

// MARK: - ExportJob

/// Represents a single export job with its configuration and state.
struct ExportJob: Codable, Equatable, Hashable, Sendable {

    /// Unique identifier.
    let id: String

    /// User-visible label.
    let label: String

    /// Export configuration.
    let config: ExportConfig

    /// Current status.
    let status: ExportJobStatus

    /// Priority level.
    let priority: ExportJobPriority

    /// Current progress (0.0 to 1.0).
    let progress: Double

    /// Path to the output file (set on completion).
    let outputPath: String?

    /// Output file size in bytes.
    let outputSizeBytes: Int?

    /// Error message (set on failure).
    let errorMessage: String?

    /// When the job was created.
    let createdAt: Date

    /// When export started (nil if queued).
    let startedAt: Date?

    /// When export completed or failed (nil if still in progress).
    let completedAt: Date?

    // MARK: - Init with defaults

    init(
        id: String,
        label: String,
        config: ExportConfig,
        status: ExportJobStatus = .queued,
        priority: ExportJobPriority = .normal,
        progress: Double = 0.0,
        outputPath: String? = nil,
        outputSizeBytes: Int? = nil,
        errorMessage: String? = nil,
        createdAt: Date,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.config = config
        self.status = status
        self.priority = priority
        self.progress = progress
        self.outputPath = outputPath
        self.outputSizeBytes = outputSizeBytes
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    // MARK: - Computed Properties

    /// Whether the job is currently active (not terminal).
    var isActive: Bool {
        status != .completed && status != .failed && status != .cancelled
    }

    /// Whether the job is in a terminal state.
    var isTerminal: Bool {
        status == .completed || status == .failed || status == .cancelled
    }

    /// Whether the job is currently running.
    var isRunning: Bool {
        status == .preparing || status == .rendering ||
        status == .encoding || status == .saving
    }

    /// Duration of the export (nil if not started or not completed).
    var exportDuration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    /// Human-readable output size.
    var outputSizeString: String {
        guard let sizeBytes = outputSizeBytes else { return "" }
        let mb = Double(sizeBytes) / (1024.0 * 1024.0)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.1f MB", mb)
    }

    // MARK: - with(...)

    func with(
        id: String? = nil,
        label: String? = nil,
        config: ExportConfig? = nil,
        status: ExportJobStatus? = nil,
        priority: ExportJobPriority? = nil,
        progress: Double? = nil,
        outputPath: String?? = nil,
        outputSizeBytes: Int?? = nil,
        errorMessage: String?? = nil,
        createdAt: Date? = nil,
        startedAt: Date?? = nil,
        completedAt: Date?? = nil
    ) -> ExportJob {
        ExportJob(
            id: id ?? self.id,
            label: label ?? self.label,
            config: config ?? self.config,
            status: status ?? self.status,
            priority: priority ?? self.priority,
            progress: progress ?? self.progress,
            outputPath: outputPath ?? self.outputPath,
            outputSizeBytes: outputSizeBytes ?? self.outputSizeBytes,
            errorMessage: errorMessage ?? self.errorMessage,
            createdAt: createdAt ?? self.createdAt,
            startedAt: startedAt ?? self.startedAt,
            completedAt: completedAt ?? self.completedAt
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: ExportJob, rhs: ExportJob) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case config
        case status
        case priority
        case progress
        case outputPath
        case outputSizeBytes
        case errorMessage
        case createdAt
        case startedAt
        case completedAt
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        config = try container.decode(ExportConfig.self, forKey: .config)

        let statusStr = try container.decodeIfPresent(String.self, forKey: .status)
        status = statusStr.flatMap { ExportJobStatus(rawValue: $0) } ?? .queued

        let priorityStr = try container.decodeIfPresent(String.self, forKey: .priority)
        priority = priorityStr.flatMap { ExportJobPriority(rawValue: $0) } ?? .normal

        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0.0
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        outputSizeBytes = try container.decodeIfPresent(Int.self, forKey: .outputSizeBytes)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)

        let createdAtStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()

        if let startedAtStr = try container.decodeIfPresent(String.self, forKey: .startedAt) {
            startedAt = ISO8601DateFormatter().date(from: startedAtStr)
        } else {
            startedAt = nil
        }

        if let completedAtStr = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = ISO8601DateFormatter().date(from: completedAtStr)
        } else {
            completedAt = nil
        }
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(config, forKey: .config)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(priority.rawValue, forKey: .priority)
        try container.encode(progress, forKey: .progress)
        try container.encodeIfPresent(outputPath, forKey: .outputPath)
        try container.encodeIfPresent(outputSizeBytes, forKey: .outputSizeBytes)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        try container.encodeIfPresent(startedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: .startedAt)
        try container.encodeIfPresent(completedAt.map { ISO8601DateFormatter().string(from: $0) }, forKey: .completedAt)
    }
}
