import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable { case ko, en }
public enum CoachID: String, Codable, CaseIterable, Sendable { case mina, jae, noa, sol }
public enum RecordingOwner: String, Codable, Sendable { case phone, watch }
public enum RunPhase: String, Codable, Sendable {
    case preparing, running, paused, ending, saved, interrupted
    public var isActive: Bool { self == .running || self == .paused }
    public var isFinished: Bool { self == .saved || self == .interrupted }
}
public enum HealthSaveState: String, Codable, Sendable { case notRequested, pending, saved, failed, uncertain }
public enum WorkoutKind: String, Codable, CaseIterable, Sendable { case free, easy, distance, intervals }

public struct WorkoutStage: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var labelKo: String
    public var labelEn: String
    public var durationSeconds: Double

    public init(id: UUID = UUID(), labelKo: String, labelEn: String, durationSeconds: Double) {
        self.id = id
        self.labelKo = labelKo
        self.labelEn = labelEn
        self.durationSeconds = durationSeconds
    }
    public func label(in language: AppLanguage) -> String { language == .ko ? labelKo : labelEn }
}

public struct WorkoutPrescription: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: WorkoutKind
    public var goalMeters: Double?
    public var stages: [WorkoutStage]

    public init(id: UUID = UUID(), kind: WorkoutKind, goalMeters: Double? = nil, stages: [WorkoutStage] = []) {
        self.id = id
        self.kind = kind
        self.goalMeters = goalMeters
        self.stages = stages
    }
    public static var free: Self { Self(kind: .free) }
    public static var easy30: Self {
        Self(kind: .easy, stages: [WorkoutStage(labelKo: "편안하게 달리기", labelEn: "Easy run", durationSeconds: 1_800)])
    }
    public static var distance5K: Self { Self(kind: .distance, goalMeters: 5_000) }
    public static var intervals: Self {
        var stages = [WorkoutStage(labelKo: "준비 운동", labelEn: "Warm up", durationSeconds: 300)]
        for repetition in 1...6 {
            stages.append(WorkoutStage(labelKo: "달리기 \(repetition)/6", labelEn: "Run \(repetition)/6", durationSeconds: 60))
            stages.append(WorkoutStage(labelKo: "회복 \(repetition)/6", labelEn: "Recover \(repetition)/6", durationSeconds: 60))
        }
        stages.append(WorkoutStage(labelKo: "마무리 운동", labelEn: "Cool down", durationSeconds: 480))
        return Self(kind: .intervals, stages: stages)
    }
    public var plannedDuration: Double { stages.reduce(0) { $0 + $1.durationSeconds } }
    public func stage(at activeSeconds: Double) -> (stage: WorkoutStage, remaining: Double, index: Int)? {
        guard activeSeconds.isFinite, activeSeconds >= 0 else { return nil }
        var end: Double = 0
        for (index, stage) in stages.enumerated() {
            end += stage.durationSeconds
            if activeSeconds < end { return (stage, end - activeSeconds, index) }
        }
        return nil
    }
    public func validate() throws {
        guard goalMeters.map({ $0.isFinite && $0 > 0 && $0 <= 1_000_000 }) ?? true,
              stages.count <= 500,
              stages.allSatisfy({ $0.durationSeconds.isFinite && $0.durationSeconds > 0 && $0.durationSeconds <= 86_400 }),
              Set(stages.map(\.id)).count == stages.count else { throw RunError.invalidPrescription }
        if kind == .distance && goalMeters == nil { throw RunError.invalidPrescription }
        if (kind == .easy || kind == .intervals) && stages.isEmpty { throw RunError.invalidPrescription }
    }
}

public struct TimedMetric: Codable, Sendable, Equatable {
    public var value: Double
    public var observedAt: Date
    public var receivedAt: Date
    public var source: RecordingOwner
    public init(value: Double, observedAt: Date, receivedAt: Date = Date(), source: RecordingOwner) {
        self.value = value
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.source = source
    }
    public func isFresh(at now: Date = Date(), maxAge: TimeInterval = 15) -> Bool {
        guard value.isFinite, maxAge >= 0 else { return false }
        let sampleAge = now.timeIntervalSince(observedAt)
        let receiveAge = now.timeIntervalSince(receivedAt)
        // A future timestamp is a clock-quality problem, not a fresh measurement.
        return sampleAge >= 0 && sampleAge <= maxAge && receiveAge >= 0 && receivedAt >= observedAt
    }
}

public struct RoutePoint: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?
    public var horizontalAccuracy: Double
    public var timestamp: Date
    public init(latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

public enum RunCommand: String, Codable, Sendable { case pause, resume, finish }
public enum RunError: String, Error, Codable, Sendable {
    case invalidTransition, staleRevision, expiredCommand, wrongRun, unsupportedSchema
    case invalidPrescription, invalidMeasurement, staleSnapshot, deletedRun, eventConflict, corruptRecord
}

public struct RunRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var owner: RecordingOwner
    public var coach: CoachID
    public var language: AppLanguage
    public var prescription: WorkoutPrescription
    public var phase: RunPhase
    public var revision: Int
    public var startedAt: Date?
    public var endedAt: Date?
    public var activeSeconds: Double
    public var distanceMeters: Double
    public var heartRate: TimedMetric?
    public var cadence: TimedMetric?
    public var power: TimedMetric?
    public var healthState: HealthSaveState
    public var healthWorkoutID: UUID?
    public var routeState: HealthSaveState
    public var route: [RoutePoint]
    public var commandIDs: [UUID]

    public init(id: UUID = UUID(), owner: RecordingOwner, coach: CoachID = .mina,
                language: AppLanguage = .ko, prescription: WorkoutPrescription = .free) {
        self.id = id; self.owner = owner; self.coach = coach; self.language = language
        self.prescription = prescription; self.phase = .preparing; self.revision = 0
        self.activeSeconds = 0; self.distanceMeters = 0; self.healthState = .notRequested
        self.routeState = .notRequested; self.route = []; self.commandIDs = []
    }

    public mutating func begin(at date: Date) throws {
        if phase == .running { return }
        guard phase == .preparing else { throw RunError.invalidTransition }
        try prescription.validate()
        startedAt = date; phase = .running; revision += 1
    }

    @discardableResult
    public mutating func apply(_ command: RunCommand, commandID: UUID, expectedRevision: Int,
                               expiresAt: Date, now: Date) throws -> Bool {
        // Return an acknowledgement for a duplicate without reapplying its effect.
        if commandIDs.contains(commandID) { return false }
        guard now <= expiresAt else { throw RunError.expiredCommand }
        guard expectedRevision == revision else { throw RunError.staleRevision }
        switch (command, phase) {
        case (.pause, .running): phase = .paused
        case (.resume, .paused): phase = .running
        case (.finish, .running), (.finish, .paused), (.finish, .interrupted):
            phase = .ending; endedAt = now
        default: throw RunError.invalidTransition
        }
        commandIDs.append(commandID); revision += 1
        return true
    }

    public mutating func checkpoint(activeSeconds: Double, distanceMeters: Double? = nil) {
        if activeSeconds.isFinite && activeSeconds >= self.activeSeconds { self.activeSeconds = activeSeconds }
        if let distanceMeters, distanceMeters.isFinite, distanceMeters >= self.distanceMeters {
            self.distanceMeters = distanceMeters
        }
    }

    public mutating func markSaved(at date: Date) {
        guard phase == .ending || phase == .interrupted else { return }
        endedAt = endedAt ?? date; phase = .saved; revision += 1
    }

    public var averagePaceSecondsPerKilometer: Double? {
        distanceMeters > 0 && activeSeconds > 0 ? activeSeconds / distanceMeters * 1_000 : nil
    }

    public func validate() throws {
        try prescription.validate()
        guard activeSeconds.isFinite, activeSeconds >= 0, distanceMeters.isFinite, distanceMeters >= 0,
              revision >= 0, [heartRate, cadence, power].compactMap({ $0 }).allSatisfy({ $0.value.isFinite }) else {
            throw RunError.invalidMeasurement
        }
    }
}
