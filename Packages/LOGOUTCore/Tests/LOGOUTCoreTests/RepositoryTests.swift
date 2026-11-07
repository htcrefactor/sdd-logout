import Foundation
import Testing
@testable import LOGOUTCore

struct RepositoryTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func duplicateEventCannotCreateAnotherRunOrJournalEntry() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .watch)
        try record.begin(at: start)
        let event = UUID()
        #expect(try await repository.save(record, eventID: event, eventKind: "commit"))
        #expect(try await repository.save(record, eventID: event, eventKind: "commit") == false)
        #expect(try await repository.records().count == 1)
        #expect(try await repository.journalEvents(for: record.id).count == 1)
        let replay = try await repository.replay(id: record.id)
        #expect(replay == record)
    }

    @Test func staleSnapshotIsRejectedWithoutDamagingJournal() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        let stale = record
        record.checkpoint(activeSeconds: 60, distanceMeters: 200)
        try await repository.save(record, eventKind: "checkpoint")
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(stale, eventKind: "late") }
        #expect(try await repository.load(id: record.id)?.activeSeconds == 60)
        #expect(try await repository.journalEvents(for: record.id).count == 1)
    }

    @Test func routeBatchesAreDurableAndIdempotent() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        try await repository.save(record, eventKind: "start")
        let points = (0..<600).map { point(second: $0) }
        let batchID = UUID()
        #expect(try await repository.appendRoute(points, to: record.id, batchID: batchID))
        #expect(try await repository.appendRoute(points, to: record.id, batchID: batchID) == false)
        #expect(try await repository.records().first?.route.isEmpty == true)
        #expect(try await repository.load(id: record.id)?.route == points)
        record.healthState = .uncertain
        try await repository.save(record, eventKind: "health.uncertain")
        #expect(try await repository.load(id: record.id)?.route.count == 600)
        #expect(try await repository.replay(id: record.id)?.healthState == .uncertain)
    }

    @Test func newerRevisionCannotReopenEndedRun() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        try record.apply(.finish, commandID: UUID(), expectedRevision: record.revision,
                         expiresAt: start.addingTimeInterval(10), now: start)
        try await repository.save(record, eventKind: "ending")
        var reopened = record
        reopened.phase = .running
        reopened.revision += 1
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(reopened, eventKind: "late.running") }
        record.markSaved(at: start)
        try await repository.save(record, eventKind: "saved")
        var interrupted = record
        interrupted.phase = .interrupted
        interrupted.revision += 1
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(interrupted, eventKind: "late.interrupted") }
        record.healthState = .saved
        try await repository.save(record, eventKind: "health.saved")
        #expect(try await repository.load(id: record.id)?.phase == .saved)
        #expect(try await repository.load(id: record.id)?.healthState == .saved)
    }

    @Test func reorderedDistanceCheckpointCannotOverwriteLaterProgress() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        record.checkpoint(activeSeconds: 100, distanceMeters: 400)
        try await repository.save(record, eventKind: "checkpoint")
        var lowerDistance = record
        lowerDistance.activeSeconds = 105
        lowerDistance.distanceMeters = 399
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(lowerDistance, eventKind: "reordered") }
        var lowerRevision = record
        lowerRevision.revision = 0
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(lowerRevision, eventKind: "stale.revision") }
        #expect(try await repository.load(id: record.id)?.distanceMeters == 400)
    }

    @Test func oldMetadataCannotEraseSuccessfulHealthSaveOrRewriteStateWithoutRevision() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        record.healthState = .saved
        record.healthWorkoutID = UUID()
        try await repository.save(record, eventKind: "health.saved")
        var staleHealth = record
        staleHealth.healthState = .pending
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(staleHealth, eventKind: "health.pending") }
        var wrongWorkout = record
        wrongWorkout.healthWorkoutID = UUID()
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(wrongWorkout, eventKind: "health.wrong") }
        var wrongPhase = record
        wrongPhase.phase = .paused
        await #expect(throws: RunError.staleSnapshot) { try await repository.save(wrongPhase, eventKind: "pause.without.revision") }
        #expect(try await repository.load(id: record.id)?.healthWorkoutID == record.healthWorkoutID)
    }

    @Test func cumulativeRouteOnlyWritesNewPoints() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        record.route = [point(second: 0), point(second: 1)]
        try await repository.save(record, eventKind: "checkpoint")
        record.route.append(point(second: 2))
        try await repository.save(record, eventKind: "checkpoint")
        #expect(try await repository.load(id: record.id)?.route.count == 3)
        #expect(try await repository.replay(id: record.id)?.route == record.route)
    }

    @Test func incrementalCheckpointCommitsSnapshotAndRouteAtomically() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        let firstBatch = [point(second: 0), point(second: 1)]
        let eventID = UUID()
        record.checkpoint(activeSeconds: 1, distanceMeters: 2)
        #expect(try await repository.save(record, routeBatch: firstBatch, eventID: eventID, eventKind: "checkpoint"))
        #expect(try await repository.save(record, routeBatch: firstBatch, eventID: eventID, eventKind: "checkpoint") == false)
        record.checkpoint(activeSeconds: 2, distanceMeters: 4)
        try await repository.save(record, routeBatch: [point(second: 2)], eventKind: "checkpoint")
        let loaded = try await repository.load(id: record.id)
        #expect(loaded?.route.count == 3)
        #expect(loaded?.activeSeconds == 2)
        #expect(loaded?.distanceMeters == 4)
        #expect(try await repository.replay(id: record.id) == loaded)
    }

    @Test func invalidIncrementalCheckpointRollsBackMetricsAndRouteTogether() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        try record.begin(at: start)
        record.checkpoint(activeSeconds: 2, distanceMeters: 4)
        try await repository.save(record, routeBatch: [point(second: 0), point(second: 1)], eventKind: "checkpoint")
        record.checkpoint(activeSeconds: 3, distanceMeters: 6)
        await #expect(throws: RunError.eventConflict) {
            try await repository.save(record, routeBatch: [point(second: 1), point(second: 2)], eventKind: "invalid")
        }
        let loaded = try await repository.load(id: record.id)
        #expect(loaded?.route.count == 2)
        #expect(loaded?.activeSeconds == 2)
        #expect(loaded?.distanceMeters == 4)
        #expect(try await repository.journalEvents(for: record.id).count == 1)
    }

    @Test func deletionTombstoneRejectsDelayedCompanionReplay() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .watch)
        try record.begin(at: start)
        try await repository.save(record, eventKind: "start")
        try await repository.delete(id: record.id)
        try await repository.delete(id: record.id)
        #expect(try await repository.load(id: record.id) == nil)
        #expect(try await repository.records().isEmpty)
        #expect(try await repository.journalEvents(for: record.id).isEmpty)
        await #expect(throws: RunError.deletedRun) { try await repository.save(record, eventKind: "late.sync") }
    }

    @Test func sqliteReopenPreservesInitialSchemaAndRecoveryState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LOGOUTCore-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try RunRepository(directory: directory)
        var record = RunRecord(owner: .phone, coach: .jae, language: .en, prescription: .intervals)
        try record.begin(at: start)
        record.checkpoint(activeSeconds: 345, distanceMeters: 900)
        record.route = [point(second: 0), point(second: 1)]
        record.healthState = .pending
        try await first.save(record, eventKind: "checkpoint")
        let reopened = try RunRepository(directory: directory)
        let loaded = try await reopened.load(id: record.id)
        #expect(loaded == record)
        #expect(try await reopened.unfinished().map(\.id) == [record.id])
        #expect(try await reopened.replay(id: record.id) == record)
        let resourceValues = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(resourceValues.isExcludedFromBackup == true)
    }

    @Test func invalidRouteRollsBackSnapshotAndEvent() async throws {
        let repository = try RunRepository(inMemory: true)
        var record = RunRecord(owner: .phone)
        record.route = [point(second: 0), point(second: 0)]
        await #expect(throws: RunError.invalidMeasurement) { try await repository.save(record, eventKind: "invalid") }
        #expect(try await repository.records().isEmpty)
        #expect(try await repository.journalEvents(for: record.id).isEmpty)
    }

    private func point(second: Int) -> RoutePoint {
        RoutePoint(latitude: 37 + Double(second) * 0.00001, longitude: 127, horizontalAccuracy: 5,
                   timestamp: start.addingTimeInterval(Double(second)))
    }
}
