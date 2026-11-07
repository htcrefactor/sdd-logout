import Foundation
import Testing
@testable import LOGOUTCore

struct RecordingTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func commandRetriesCannotDuplicateTransitions() throws {
        var run = RunRecord(owner: .watch)
        try run.begin(at: start)
        let commandID = UUID()
        #expect(try run.apply(.pause, commandID: commandID, expectedRevision: 1,
                              expiresAt: start.addingTimeInterval(30), now: start))
        #expect(run.phase == .paused)
        #expect(run.revision == 2)
        #expect(try run.apply(.pause, commandID: commandID, expectedRevision: 1,
                              expiresAt: start, now: start.addingTimeInterval(100)) == false)
        #expect(run.revision == 2)
        #expect(run.commandIDs == [commandID])
    }

    @Test func staleAndExpiredCommandsDoNotChangeState() throws {
        var run = RunRecord(owner: .phone)
        try run.begin(at: start)
        #expect(throws: RunError.staleRevision) {
            try run.apply(.finish, commandID: UUID(), expectedRevision: 0,
                          expiresAt: start.addingTimeInterval(5), now: start)
        }
        #expect(throws: RunError.expiredCommand) {
            try run.apply(.finish, commandID: UUID(), expectedRevision: 1,
                          expiresAt: start.addingTimeInterval(-1), now: start)
        }
        #expect(run.phase == .running)
        #expect(run.endedAt == nil)
    }

    @Test func completedRunHasOneEndingAndOneSavedTransition() throws {
        var run = RunRecord(owner: .phone)
        try run.begin(at: start)
        run.checkpoint(activeSeconds: 120, distanceMeters: 400)
        let endID = UUID()
        try run.apply(.finish, commandID: endID, expectedRevision: 1, expiresAt: start.addingTimeInterval(180),
                      now: start.addingTimeInterval(120))
        run.markSaved(at: start.addingTimeInterval(125))
        let revision = run.revision
        run.markSaved(at: start.addingTimeInterval(200))
        #expect(run.revision == revision)
        #expect(run.endedAt == start.addingTimeInterval(120))
        #expect(try run.apply(.finish, commandID: endID, expectedRevision: 1, expiresAt: start, now: start) == false)
        #expect(run.phase == .saved)
        #expect(run.averagePaceSecondsPerKilometer == 300)
    }

    @Test func monotonicClockExcludesPausesAndSurvivesIrregularCallbacks() {
        var clock = RunClock()
        clock.start(uptime: 100)
        #expect(clock.elapsed(at: 137.5) == 37.5)
        clock.checkpoint(uptime: 137.5)
        clock.pause(uptime: 150)
        #expect(clock.elapsed(at: 9_000) == 50)
        clock.resume(uptime: 9_000)
        #expect(clock.elapsed(at: 9_025) == 75)
        clock.resume(uptime: 9_020)
        #expect(clock.elapsed(at: 9_025) == 75)
    }

    @Test func lowerUptimeRequiresExplicitRecovery() {
        var clock = RunClock(activeSeconds: 80)
        clock.start(uptime: 1_000)
        clock.checkpoint(uptime: 1_010)
        clock.checkpoint(uptime: 4)
        #expect(clock.requiresReconciliation)
        #expect(clock.elapsed(at: 5_000) == 90)
        clock.resume(uptime: 8)
        #expect(!clock.isRunning)
        var recovered = RunClock(activeSeconds: clock.accumulatedSeconds)
        #expect(!recovered.isRunning)
        recovered.start(uptime: 8)
        #expect(recovered.elapsed(at: 18) == 100)
    }

    @Test func workoutStagesUseOneExactPrescription() throws {
        let workout = WorkoutPrescription.intervals
        try workout.validate()
        #expect(workout.plannedDuration == 1_500)
        #expect(workout.stages.count == 14)
        #expect(workout.stage(at: 299)?.remaining == 1)
        #expect(workout.stage(at: 300)?.index == 1)
        #expect(workout.stage(at: 360)?.index == 2)
        #expect(workout.stage(at: 1_500) == nil)
        #expect(WorkoutPrescription.free.stage(at: 1_000) == nil)
    }

    @Test func staleOrFutureMetricsAreNotCurrent() {
        let metric = TimedMetric(value: 151, observedAt: start, receivedAt: start.addingTimeInterval(2), source: .watch)
        #expect(metric.isFresh(at: start.addingTimeInterval(14)))
        #expect(!metric.isFresh(at: start.addingTimeInterval(16)))
        #expect(!metric.isFresh(at: start.addingTimeInterval(-1)))
        let futureSample = TimedMetric(value: 151, observedAt: start.addingTimeInterval(60), receivedAt: start, source: .watch)
        #expect(!futureSample.isFresh(at: start))
        #expect(!TimedMetric(value: .nan, observedAt: start, source: .phone).isFresh(at: start))
    }

    @Test func gpsRejectsBadFixesWithoutAddingDistance() {
        var gps = GPSAccumulator()
        let first = point(latitude: 37, second: 0)
        #expect(gps.ingest(first, now: start)?.distanceMeters == 0)
        #expect(gps.ingest(first, now: start) == nil)
        #expect(gps.ingest(point(latitude: 38, second: 1), now: start.addingTimeInterval(1)) == nil)
        #expect(gps.ingest(point(latitude: 37.00005, second: 1, accuracy: 80), now: start.addingTimeInterval(1)) == nil)
        #expect(gps.ingest(point(latitude: 37.00005, second: 1), now: start.addingTimeInterval(40)) == nil)
        let update = gps.ingest(point(latitude: 37.00005, second: 1), now: start.addingTimeInterval(1))
        #expect(update != nil)
        #expect(abs(gps.distanceMeters - 5.56) < 0.1)
    }

    @Test func gpsDoesNotBridgePauseOrUnobservedGap() {
        var gps = GPSAccumulator()
        _ = gps.ingest(point(latitude: 37, second: 0), now: start)
        _ = gps.ingest(point(latitude: 37.00005, second: 1), now: start.addingTimeInterval(1))
        let distance = gps.distanceMeters
        gps.breakSegment()
        let resumed = gps.ingest(point(latitude: 38, second: 60), now: start.addingTimeInterval(60))
        #expect(resumed?.startsNewSegment == true)
        #expect(resumed?.incrementMeters == 0)
        let afterGap = gps.ingest(point(latitude: 39, second: 100), now: start.addingTimeInterval(100))
        #expect(afterGap?.startsNewSegment == true)
        #expect(gps.distanceMeters == distance)
    }

    @Test func wireRejectsOtherRunAndUnsupportedSchema() throws {
        let run = RunRecord(owner: .watch)
        var message = DeviceMessage(kind: .commit, runID: UUID(), revision: 0, expiresAt: start.addingTimeInterval(10))
        #expect(throws: RunError.wrongRun) { try message.validate(for: run, now: start) }
        message.runID = run.id
        message.schemaVersion = 99
        #expect(throws: RunError.unsupportedSchema) { try message.validate(for: run, now: start) }
    }

    private func point(latitude: Double, second: Double, accuracy: Double = 4) -> RoutePoint {
        RoutePoint(latitude: latitude, longitude: 127, horizontalAccuracy: accuracy, timestamp: start.addingTimeInterval(second))
    }
}
