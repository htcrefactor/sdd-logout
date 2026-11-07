import Combine
import Foundation
import HealthKit
import LOGOUTCore
import WatchKit

/// The Watch is the sole writer for a Watch-owned workout. A launch request or
/// connection alone is never permission to start recording.
@MainActor
final class WatchRunModel: ObservableObject {
    static let shared = WatchRunModel()

    @Published private(set) var record: RunRecord?
    @Published private(set) var seconds: Double = 0
    @Published private(set) var busy = false
    @Published private(set) var localSaved = false
    @Published private(set) var phoneSynced = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentPace: TimedMetric?
    @Published private(set) var routeAvailable = false
    @Published private(set) var language: AppLanguage
    @Published private(set) var restoring = true

    let recorder = WorkoutRecorder()
    let link = DeviceLink()
    let location = LocationTracker()

    private let repository: RunRepository?
    private var clock = RunClock()
    private var latestMeasurements: WorkoutMeasurements?
    private var pendingRoute: [RoutePoint] = []
    private var timerTask: Task<Void, Never>?
    private var checkpointTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var lastCheckpointUptime: Double = 0
    private var lastDeliveryUptime: Double = 0
    private var lastStageIndex: Int?
    private var goalAnnounced = false
    private var preparationExpiry: Date?
    private var preparationCommandID: UUID?
    private var recoveryTask: Task<Void, Never>?
    private var stateDurable = true

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "ko") ?? .ko
        do { repository = try RunRepository() }
        catch { repository = nil }

        link.onMessage = { [weak self] message in
            guard let self else { throw DeviceLink.LinkError.unavailable }
            return try await self.receive(message)
        }
        link.onReachabilityChange = { [weak self] reachable in
            guard let self, reachable else { return }
            self.sendSnapshot()
            self.link.retryPendingTransfers()
        }
        link.onCompletedReceipt = { [weak self] id in
            UserDefaults.standard.set(true, forKey: "phoneReceipt.\(id.uuidString)")
            if self?.record?.id == id { self?.phoneSynced = true }
        }
        link.onLanguageChange = { [weak self] preference in
            guard let self else { return }
            UserDefaults.standard.set(preference.rawValue, forKey: "appLanguage")
            if self.record == nil || self.record?.phase.isFinished == true { self.language = preference }
        }
        recorder.onMeasurements = { [weak self] measurements in self?.latestMeasurements = measurements }
        recorder.onStateChange = { [weak self] state, date in
            Task { @MainActor in await self?.sessionChanged(state, at: date) }
        }
        recorder.onRemoteData = { [weak self] data in
            Task { @MainActor in
                guard let self, let message = try? JSONDecoder().decode(DeviceMessage.self, from: data) else { return }
                do {
                    if let response = try await self.receive(message) {
                        try await self.recorder.sendRemote(JSONEncoder().encode(response))
                    }
                } catch { self.sendSnapshot() }
            }
        }
        recorder.onMirrorStarted = { [weak self] in self?.sendSnapshot() }
        recorder.onError = { [weak self] _ in
            guard let self else { return }
            self.errorMessage = self.text("측정 연결을 확인하고 있어요. 저장된 기록은 유지됩니다.", "Checking workout measurements. Saved data is retained.")
        }
        location.onUpdate = { [weak self] update in
            guard let self, self.record?.phase == .running else { return }
            // A full disk must not cause unbounded health data growth in memory.
            guard self.pendingRoute.count < 4_096 else {
                self.routeAvailable = false
                self.errorMessage = self.text("저장 공간 부족으로 경로 일부를 보관하지 못했어요. 운동 측정은 계속됩니다.", "Some route points could not be retained because storage is full. Workout measurements continue.")
                return
            }
            self.pendingRoute.append(update.point)
            self.routeAvailable = true
            if let pace = update.paceSecondsPerKilometer {
                self.currentPace = TimedMetric(value: pace, observedAt: update.point.timestamp, source: .watch)
            }
            self.recorder.appendLocations([update.location])
        }
        location.onError = { [weak self] _ in
            self?.routeAvailable = false
            self?.currentPace = nil
        }
        link.activate()
        recoveryTask = Task { await restore() }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func text(_ ko: String, _ en: String) -> String { language == .ko ? ko : en }

    func authorizeHealth() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await recorder.requestAuthorization()
            errorMessage = nil
            Task { @MainActor in link.processStagedPreparation() }
        } catch {
            errorMessage = text("건강 접근을 허용한 뒤 iPhone에서 다시 시도하세요.", "Allow Health access, then retry from your iPhone.")
        }
    }

    func handleWorkoutLaunch() {
        // HKHealthStore.startWatchApp launches the app; the matching staged
        // prescription, followed by an explicit commit, authorizes recording.
        link.processStagedPreparation()
    }

    func handleActiveRecovery() {
        guard recoveryTask == nil else { return }
        recoveryTask = Task { await restore() }
    }

    func perform(_ command: RunCommand) async {
        guard let record, !busy else { return }
        let message = DeviceMessage(kind: .command, runID: record.id, revision: record.revision,
                                    expiresAt: Date().addingTimeInterval(15), command: command)
        do {
            _ = try await receive(message)
            sendSnapshot()
        } catch {
            errorMessage = text("변경을 확인하지 못했어요. 현재 운동 상태를 확인한 뒤 다시 시도하세요.", "Could not confirm the change. Check the workout state and try again.")
        }
    }

    func retryLocalSave() async {
        guard let record, record.phase.isFinished, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await persist(record, kind: "watch.save.retry")
            try await flushRoute()
            stateDurable = true
            localSaved = true
            try await queueCompletion()
            errorMessage = nil
        } catch {
            errorMessage = text("아직 안전하게 저장하지 못했어요. 앱을 열어 둔 채 다시 시도하세요.", "The run is not safely saved yet. Keep the app open and retry.")
        }
    }

    func retryPhoneSync() {
        Task {
            do { try await queueCompletion() }
            catch { errorMessage = text("iPhone 동기화를 준비하지 못했어요. 다시 시도하세요.", "Could not prepare iPhone sync. Try again.") }
        }
    }

    func dismissSummary() {
        guard localSaved else { return }
        record = nil
        errorMessage = nil
        seconds = 0
    }

    private func receive(_ message: DeviceMessage) async throws -> DeviceMessage? {
        if restoring, let recoveryTask { await recoveryTask.value }
        guard repository != nil else { throw DeviceLink.LinkError.unavailable }
        guard message.schemaVersion == 1 else { throw RunError.unsupportedSchema }
        if message.kind == .ack { return nil }
        if message.kind == .snapshot, message.record == nil {
            guard message.expiresAt > Date(), stateDurable else { throw RunError.expiredCommand }
            if let current = record, current.id == message.runID {
                let kind: DeviceMessage.Kind = current.phase == .preparing && recorder.state == .prepared && !busy ? .ready : .snapshot
                return snapshot(current, kind: kind, commandID: message.commandID)
            }
            guard let saved = try await repository?.load(id: message.runID), saved.owner == .watch else { throw RunError.wrongRun }
            return snapshot(saved, commandID: message.commandID)
        }
        guard !busy else { throw DeviceLink.LinkError.rejected("The workout is changing state. Retry with the same command ID.") }
        busy = true
        defer { busy = false }
        // Finish a previously started checkpoint before mutating the owner state.
        await checkpointTask?.value
        checkpointTask = nil

        if message.kind == .prepare { return try await prepare(message) }
        guard var current = record, current.owner == .watch, current.id == message.runID else { throw RunError.wrongRun }

        if message.kind == .commit, current.commandIDs.contains(message.commandID), current.phase != .preparing {
            if !stateDurable { try await confirmState(current, kind: "watch.commit.retry") }
            if current.phase.isFinished { localSaved = true; try await queueCompletion() }
            return snapshot(current, kind: .snapshot, commandID: message.commandID)
        }
        if message.kind == .command, current.commandIDs.contains(message.commandID) {
            if !stateDurable { try await confirmState(current, kind: "watch.command.retry") }
            if current.phase.isFinished { localSaved = true; try await queueCompletion() }
            return snapshot(current, kind: .snapshot, commandID: message.commandID)
        }
        try message.validate(for: current)
        switch message.kind {
        case .commit:
            guard current.phase == .preparing, !current.commandIDs.contains(message.commandID),
                  recorder.state == .prepared else { throw RunError.invalidTransition }
            // Record the commit intent before touching HealthKit. An unresolved
            // intent blocks a second start and is reconciled on relaunch.
            current.commandIDs.append(message.commandID)
            try await persist(current, eventID: message.commandID, kind: "watch.commit.intent")
            record = current
            do {
                try await recorder.start()
            } catch {
                if recorder.state == .ended || recorder.state == .failed {
                    current.phase = .interrupted
                    current.revision += 1
                    current.endedAt = Date()
                    current.healthState = .uncertain
                    try await confirmState(current, kind: "watch.commit.interrupted")
                    localSaved = true
                    try await queueCompletion()
                    errorMessage = text("달리기 시작을 확인하지 못했어요. iPhone에서 기록을 확인하세요.", "The start could not be confirmed. Check the record on iPhone.")
                    return snapshot(current, commandID: message.commandID)
                }
                throw error
            }
            guard let actualStart = recorder.currentStartDate else { throw WorkoutRecorderError.invalidState }
            try current.begin(at: actualStart)
            current.checkpoint(activeSeconds: recorder.elapsedSeconds ?? current.activeSeconds)
            current.healthState = .pending
            preparationExpiry = nil
            clock = RunClock(activeSeconds: current.activeSeconds)
            clock.start(uptime: ProcessInfo.processInfo.systemUptime)
            seconds = current.activeSeconds
            lastStageIndex = current.prescription.stage(at: seconds)?.index
            record = current
            startLocation()
            try await confirmState(current, kind: "watch.commit.running")
            WKInterfaceDevice.current().play(.start)
            return snapshot(current, kind: .snapshot, commandID: message.commandID)
        case .command:
            guard let command = message.command else { throw RunError.invalidTransition }
            return try await commandRun(command, message: message, current: current)
        case .abort:
            // An abort is safe only before any commit intent was accepted.
            guard current.phase == .preparing, current.commandIDs.isEmpty else { throw RunError.invalidTransition }
            try await recorder.abortPrepared()
            current.phase = .interrupted
            current.endedAt = Date()
            current.revision += 1
            try await persist(current, eventID: message.commandID, kind: "watch.prepare.aborted")
            record = nil
            preparationExpiry = nil
            return snapshot(current, kind: .ack, commandID: message.commandID)
        default:
            throw RunError.invalidTransition
        }
    }

    private func prepare(_ message: DeviceMessage) async throws -> DeviceMessage {
        guard let proposed = message.record, proposed.owner == .watch, proposed.phase == .preparing,
              proposed.id == message.runID, proposed.commandIDs.isEmpty else { throw RunError.wrongRun }
        try message.validate(for: proposed)
        if let current = record, current.phase.isFinished, !localSaved { throw RunError.invalidTransition }
        if let current = record, current.phase.isActive || current.phase == .ending || current.phase == .preparing {
            guard current.id == proposed.id, current.revision == proposed.revision,
                  current.prescription == proposed.prescription, current.commandIDs.isEmpty else { throw RunError.invalidTransition }
            if recorder.state == .prepared {
                return snapshot(current, kind: .ready, commandID: message.commandID)
            }
        }
        try await persist(proposed, eventID: message.commandID, kind: "watch.prepare")
        record = proposed
        language = proposed.language
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        localSaved = false
        phoneSynced = false
        errorMessage = nil
        seconds = 0
        currentPace = nil
        latestMeasurements = nil
        routeAvailable = false
        pendingRoute = []
        location.reset()
        goalAnnounced = false
        preparationExpiry = message.expiresAt
        preparationCommandID = message.commandID
        do {
            guard try await recorder.prepare(record: proposed) else { throw RunError.invalidTransition }
        } catch {
            errorMessage = text("건강 접근과 iPhone 연결을 확인한 뒤 iPhone에서 다시 시도하세요.", "Check Health access and the iPhone connection, then retry from iPhone.")
            throw error
        }
        return snapshot(proposed, kind: .ready, commandID: message.commandID)
    }

    private func commandRun(_ command: RunCommand, message: DeviceMessage, current: RunRecord) async throws -> DeviceMessage {
        var changed = current
        try changed.apply(command, commandID: message.commandID, expectedRevision: message.revision,
                          expiresAt: message.expiresAt, now: Date())
        try await persist(current, eventID: message.commandID, kind: "watch.\(command.rawValue).intent")
        switch command {
        case .pause:
            try await recorder.pause()
            clock.pause(uptime: ProcessInfo.processInfo.systemUptime)
            location.pause()
            currentPace = nil
            changed = applyingMeasurements(to: changed)
            changed.checkpoint(activeSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
            seconds = changed.activeSeconds
            try await confirmState(changed, kind: "watch.pause.confirmed")
            try await flushRoute()
            WKInterfaceDevice.current().play(.click)
        case .resume:
            try await recorder.resume()
            clock.resume(uptime: ProcessInfo.processInfo.systemUptime)
            startLocation()
            try await confirmState(changed, kind: "watch.resume.confirmed")
            WKInterfaceDevice.current().play(.start)
        case .finish:
            changed = applyingMeasurements(to: changed)
            changed.checkpoint(activeSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
            changed.healthState = .pending
            if routeAvailable { changed.routeState = .pending }
            // Keep a recoverable ending record even if Health completion or the
            // next local save fails. Never repeat an ambiguous Health write.
            try await persist(changed, kind: "watch.finish.ending")
            clock.pause(uptime: ProcessInfo.processInfo.systemUptime)
            location.stop()
            currentPace = nil
            changed.checkpoint(activeSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
            record = changed
            seconds = changed.activeSeconds
            let result = await recorder.finish()
            changed = applyingMeasurements(to: changed)
            changed.checkpoint(activeSeconds: recorder.elapsedSeconds ?? changed.activeSeconds)
            changed.healthState = result.workoutState
            changed.healthWorkoutID = result.workoutID
            changed.routeState = result.routeState
            changed.markSaved(at: Date())
            record = changed
            seconds = changed.activeSeconds
            stateDurable = false
            do {
                try await persist(changed, kind: "watch.finish.saved")
                try await flushRoute()
                stateDurable = true
                localSaved = true
                try await queueCompletion()
                errorMessage = result.errorMessage == nil ? nil : text("건강 앱 저장 상태를 iPhone에서 확인하세요. 워치 기록은 보관됩니다.", "Check the Health save status on iPhone. Your Watch record is retained.")
            } catch {
                errorMessage = text("저장 확인이 필요해요. 앱을 열어 둔 채 다시 시도하세요.", "Saving needs attention. Keep the app open and retry.")
                throw error
            }
            WKInterfaceDevice.current().play(.stop)
        }
        return snapshot(changed, kind: .snapshot, commandID: message.commandID)
    }

    private func applyingMeasurements(to source: RunRecord) -> RunRecord {
        var result = source
        if let latestMeasurements {
            result.checkpoint(activeSeconds: result.activeSeconds, distanceMeters: latestMeasurements.distanceMeters)
            result.heartRate = latestMeasurements.heartRate
            result.cadence = latestMeasurements.cadence
            result.power = latestMeasurements.power
        }
        return result
    }

    private func tick() {
        guard !restoring, !busy, var current = record else { return }
        if current.phase == .preparing, let preparationExpiry, preparationExpiry < Date(), current.commandIDs.isEmpty {
            Task {
                let abort = DeviceMessage(kind: .abort, runID: current.id, revision: current.revision,
                                          expiresAt: Date().addingTimeInterval(10))
                _ = try? await receive(abort)
            }
            return
        }
        if current.phase == .preparing, recorder.state == .prepared {
            if ProcessInfo.processInfo.systemUptime - lastDeliveryUptime >= 2 {
                lastDeliveryUptime = ProcessInfo.processInfo.systemUptime
                sendSnapshot()
            }
            return
        }
        guard current.phase.isActive else { return }
        if recorder.state == .ended || recorder.state == .failed ||
            (recorder.state == .paused && current.phase == .running) ||
            (recorder.state == .running && current.phase == .paused) {
            Task { await sessionChanged(recorder.state, at: Date()) }
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        seconds = clock.elapsed(at: uptime)
        current = applyingMeasurements(to: current)
        current.checkpoint(activeSeconds: seconds)
        record = current
        if current.phase == .running { announceStage(current) }
        if uptime - lastCheckpointUptime >= 5, checkpointTask == nil {
            lastCheckpointUptime = uptime
            checkpointTask = Task {
                defer { checkpointTask = nil }
                do {
                    try await persist(current, kind: "watch.checkpoint")
                    try await flushRoute()
                    if record?.revision == current.revision { stateDurable = true }
                } catch {
                    errorMessage = text("저장 공간을 확인하세요. 기록 저장을 다시 시도하고 있어요.", "Check storage space. Retrying local recording saves.")
                }
            }
        }
        if uptime - lastDeliveryUptime >= 2 {
            lastDeliveryUptime = uptime
            sendSnapshot()
        }
    }

    private func announceStage(_ record: RunRecord) {
        let stage = record.prescription.stage(at: seconds)
        if let stage, let previous = lastStageIndex, stage.index != previous {
            WKInterfaceDevice.current().play(.notification)
        }
        lastStageIndex = stage?.index
        let reachedDistance = record.prescription.goalMeters.map { record.distanceMeters >= $0 } ?? false
        let reachedDuration = record.prescription.plannedDuration > 0 && seconds >= record.prescription.plannedDuration
        if !goalAnnounced, reachedDistance || reachedDuration {
            goalAnnounced = true
            WKInterfaceDevice.current().play(.success)
        }
    }

    private func startLocation() {
        do { try location.start() }
        catch { routeAvailable = false }
    }

    private func persist(_ record: RunRecord, eventID: UUID? = nil, kind: String) async throws {
        guard let repository else { throw DeviceLink.LinkError.unavailable }
        if let eventID {
            // Stable command IDs may already exist. Never attach newly arrived
            // route points to a duplicate journal event and then drop the batch.
            try await repository.save(record, eventID: eventID, eventKind: kind)
        } else {
            let batch = pendingRoute
            try await repository.save(record, routeBatch: batch, eventKind: kind)
            pendingRoute.removeFirst(batch.count)
        }
    }

    private func confirmState(_ current: RunRecord, kind: String) async throws {
        stateDurable = false
        record = current
        try await persist(current, kind: kind)
        stateDurable = true
    }

    private func flushRoute() async throws {
        guard let record, !pendingRoute.isEmpty else { return }
        try await persist(record, kind: "watch.route.checkpoint")
    }

    private func snapshot(_ record: RunRecord, kind: DeviceMessage.Kind = .snapshot, commandID: UUID = UUID()) -> DeviceMessage {
        var lightweight = record
        lightweight.route = []
        return DeviceMessage(kind: kind, runID: record.id, commandID: commandID, revision: record.revision,
                             expiresAt: Date().addingTimeInterval(30), record: lightweight)
    }

    private func sendSnapshot() {
        guard let record, deliveryTask == nil, !restoring, !busy, stateDurable else { return }
        let isReady = record.phase == .preparing && recorder.state == .prepared
        guard record.phase != .preparing || isReady else { return }
        let message = snapshot(record, kind: isReady ? .ready : .snapshot,
                               commandID: isReady ? preparationCommandID ?? UUID() : UUID())
        deliveryTask = Task {
            defer { deliveryTask = nil }
            do {
                try await recorder.sendRemote(JSONEncoder().encode(message))
            } catch {
                if link.isReachable { _ = try? await link.send(message) }
            }
        }
    }

    private func queueCompletion() async throws {
        guard let record, localSaved, let repository, let fullRecord = try await repository.load(id: record.id) else { return }
        try link.queueCompleted(fullRecord)
    }

    private func restore() async {
        restoring = true
        defer { restoring = false; recoveryTask = nil }
        guard let repository else {
            errorMessage = text("저장소를 열지 못했어요. 운동을 시작하기 전에 다시 실행하세요.", "Storage could not be opened. Reopen the app before starting a workout.")
            return
        }
        do {
            if var pending = try await repository.unfinished().first {
                record = pending
                language = pending.language
                if try await recorder.recover(record: pending) {
                    if pending.phase == .preparing {
                        guard !pending.commandIDs.isEmpty else { throw RunError.invalidTransition }
                        guard let actualStart = recorder.currentStartDate else { throw WorkoutRecorderError.invalidState }
                        try pending.begin(at: actualStart)
                    }
                    let running = recorder.state == .running
                    guard running || recorder.state == .paused else { throw RunError.invalidTransition }
                    pending.phase = running ? .running : .paused
                    pending.revision += 1
                    pending.checkpoint(activeSeconds: recorder.elapsedSeconds ?? pending.activeSeconds)
                    record = pending
                    stateDurable = false
                    seconds = pending.activeSeconds
                    clock = RunClock(activeSeconds: pending.activeSeconds)
                    if running {
                        clock.resume(uptime: ProcessInfo.processInfo.systemUptime)
                        startLocation()
                    }
                    lastStageIndex = pending.prescription.stage(at: seconds)?.index
                    try await persist(pending, kind: "watch.recovered")
                    stateDurable = true
                    sendSnapshot()
                } else {
                    pending.phase = .interrupted
                    pending.endedAt = pending.endedAt ?? Date()
                    pending.revision += 1
                    if pending.healthState == .pending { pending.healthState = .uncertain }
                    try await persist(pending, kind: "watch.recovery.interrupted")
                    record = pending
                    seconds = pending.activeSeconds
                    localSaved = true
                    errorMessage = text("운동이 중단되었어요. 마지막으로 저장한 기록을 보관했습니다.", "The workout was interrupted. The last saved record is retained.")
                    try await queueCompletion()
                }
            } else if let latest = try await repository.records().first(where: { $0.phase.isFinished && $0.startedAt != nil }) {
                record = latest
                language = latest.language
                seconds = latest.activeSeconds
                localSaved = true
                phoneSynced = UserDefaults.standard.bool(forKey: "phoneReceipt.\(latest.id.uuidString)")
                if !phoneSynced { try await queueCompletion() }
            }
        } catch {
            errorMessage = text("운동 복구 상태를 확인해야 해요. iPhone에서 연결 상태를 확인하세요.", "Workout recovery needs attention. Check the connection on iPhone.")
        }
    }

    private func sessionChanged(_ state: RecorderState, at date: Date) async {
        guard !busy, !restoring, var current = record, current.phase.isActive else { return }
        // Reconcile changes made by the system, such as starting another workout.
        // Expected changes from our own command are handled inside its transaction.
        let shouldPause = state == .paused && current.phase == .running
        let shouldResume = state == .running && current.phase == .paused
        let stopped = state == .ended || state == .failed
        guard shouldPause || shouldResume || stopped else { return }
        busy = true
        defer { busy = false }
        await checkpointTask?.value
        current = record ?? current
        if shouldResume {
            clock.resume(uptime: ProcessInfo.processInfo.systemUptime)
            current.phase = .running
            startLocation()
        } else {
            clock.pause(uptime: ProcessInfo.processInfo.systemUptime)
            location.pause()
            currentPace = nil
            current.phase = stopped ? .interrupted : .paused
        }
        current = applyingMeasurements(to: current)
        current.checkpoint(activeSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
        current.revision += 1
        if stopped {
            current.endedAt = date
            current.healthState = .uncertain
        }
        record = current
        stateDurable = false
        seconds = current.activeSeconds
        do {
            try await persist(current, kind: "watch.system.\(current.phase.rawValue)")
            try await flushRoute()
            stateDurable = true
            if stopped {
                localSaved = true
                errorMessage = text("운동이 중단되었어요. 저장된 기록을 iPhone에서 확인하세요.", "The workout stopped. Review the saved record on iPhone.")
                try await queueCompletion()
            }
            sendSnapshot()
        } catch {
            errorMessage = text("변경된 운동 상태를 아직 저장하지 못했어요.", "The changed workout state is not safely saved yet.")
        }
    }
}
