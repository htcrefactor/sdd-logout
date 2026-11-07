import Combine
import Foundation
import CoreLocation
import LOGOUTCore

@MainActor
final class AppModel: ObservableObject {
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language"); link.syncLanguage(language) } }
    @Published var coach: CoachID { didSet { defaults.set(coach.rawValue, forKey: "coach") } }
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var goal: String { didSet { defaults.set(goal, forKey: "goal") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    @Published private(set) var activeRun: RunRecord?
    @Published private(set) var history: [RunRecord] = []
    @Published private(set) var busy = false
    @Published private(set) var pendingControl = false
    @Published private(set) var currentPace: Double?
    @Published private(set) var displaySeconds: Double = 0
    @Published private(set) var canRetrySave = false
    @Published private(set) var ready = false
    @Published var errorMessage: String?
    @Published var recoveryMessage: String?
    @Published var summary: RunRecord?

    let recorder = WorkoutRecorder()
    let location = LocationTracker()
    let link = DeviceLink()
    private let defaults: UserDefaults
    private let repository: RunRepository?
    private var clock = RunClock()
    private var tickTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var commitID: UUID?
    private var commitInFlight = false
    private var starting = false
    private var checkpointInFlight = false
    private var lastCheckpoint = Date.distantPast
    private var lastSnapshotTime: Date?
    private var bootstrapped = false
    private var pendingRoute: [RoutePoint] = []
    private var pendingFinal: RunRecord?
    private var lastLocationAt: Date?
    private var writeInFlight = false

    init(defaults providedDefaults: UserDefaults = .standard) {
        let defaults: UserDefaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suite = "studio-glhf.logout.ui-tests"
            defaults = UserDefaults(suiteName: suite) ?? providedDefaults
            if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") { defaults.removePersistentDomain(forName: suite) }
        } else { defaults = providedDefaults }
        #else
        defaults = providedDefaults
        #endif
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .ko
        coach = CoachID(rawValue: defaults.string(forKey: "coach") ?? "") ?? .mina
        appearance = defaults.string(forKey: "appearance") ?? "auto"
        goal = defaults.string(forKey: "goal") ?? "5k"
        onboarded = defaults.bool(forKey: "onboarded")
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let inMemory = false
        #endif
        do { repository = try RunRepository(inMemory: inMemory) }
        catch { repository = nil; errorMessage = error.localizedDescription }
        for publisher in [recorder.objectWillChange, location.objectWillChange, link.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }
        configureServices()
        link.activate()
        link.syncLanguage(language)
    }

    func t(_ ko: String, _ en: String) -> String { language == .ko ? ko : en }

    var isNight: Bool {
        if appearance == "dark" { return true }
        if appearance == "light" { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 7
    }

    var watchValuesFresh: Bool {
        guard let lastSnapshotTime else { return false }
        return Date().timeIntervalSince(lastSnapshotTime) <= 15
    }

    var freshCurrentPace: Double? {
        guard activeRun?.phase == .running, let lastLocationAt,
              Date().timeIntervalSince(lastLocationAt) < 15 else { return nil }
        return currentPace
    }

    func bootstrap() async {
        guard !bootstrapped, let repository else { return }
        bootstrapped = true
        do {
            history = try await repository.records().filter { $0.phase == .saved || $0.phase == .interrupted }
            let pending = try await repository.unfinished()
            ready = true
            guard let recovered = pending.first else { return }
            activeRun = recovered
            displaySeconds = recovered.activeSeconds
            recoveryMessage = t("이전 달리기를 복구했어요. 연결이 끊긴 구간은 기록이 불완전할 수 있어요.", "A previous run was recovered. Measurements during the interruption may be incomplete.")
            if recovered.owner == .phone,
               try await recorder.recover(record: recovered) {
                var restored = recovered
                restored.startedAt = recorder.currentStartDate ?? recovered.startedAt
                restored.phase = recorder.state == .paused ? .paused : .running
                restored.revision += 1
                restored.checkpoint(activeSeconds: recorder.elapsedSeconds ?? recovered.activeSeconds)
                activeRun = restored
                displaySeconds = restored.activeSeconds
                clock = RunClock(activeSeconds: restored.activeSeconds)
                location.reset(distanceMeters: restored.distanceMeters)
                if recorder.state == .running {
                    clock.start(uptime: ProcessInfo.processInfo.systemUptime)
                    do { try location.start() } catch { recoveryMessage = error.localizedDescription }
                }
                startTicker()
                try await persist(restored, kind: "recovery.adopted")
            } else if recovered.owner == .phone {
                // Never resume a lost recording by guessing elapsed wall-clock time.
                var interrupted = recovered
                interrupted.phase = .interrupted
                interrupted.endedAt = Date()
                interrupted.revision += 1
                if interrupted.healthState == .pending { interrupted.healthState = .uncertain }
                _ = try await repository.save(interrupted, eventKind: "recovery.interrupted")
                activeRun = nil
                summary = interrupted
                await reloadHistory()
            } else {
                // Owner remains Watch. A mirror/reconciliation must establish its state.
                startTicker()
                await requestWatchState()
            }
        } catch { ready = false; bootstrapped = false; errorMessage = error.localizedDescription }
    }

    func requestHealth() async {
        do { try await recorder.requestAuthorization() }
        catch { errorMessage = error.localizedDescription }
    }

    func start(_ prescription: WorkoutPrescription, owner: RecordingOwner) async {
        guard ready, activeRun == nil, !starting, let repository else { return }
        guard location.isAuthorized else {
            errorMessage = t("위치 접근을 허용한 후 시작해 주세요.", "Allow location access before starting.")
            return
        }
        starting = true; busy = true
        defer { starting = false; busy = false }
        currentPace = nil; recoveryMessage = nil; commitID = nil
        pendingRoute = []; pendingFinal = nil; canRetrySave = false; lastLocationAt = nil
        var record = RunRecord(owner: owner, coach: coach, language: language, prescription: prescription)
        do {
            _ = try await repository.save(record, eventKind: "run.preparing")
            activeRun = record
            if owner == .watch {
                guard link.isCompanionInstalled else { throw AppError.watchUnavailable }
                let preparation = DeviceMessage(kind: .prepare, runID: record.id, revision: record.revision,
                                                expiresAt: Date().addingTimeInterval(120), record: record)
                try link.stagePreparation(preparation)
                try await recorder.launchWatch()
                if link.isReachable, let reply = try await link.send(preparation) {
                    _ = try await receive(reply)
                }
                // A late ready event follows the same path. There is no automatic phone fallback.
                return
            }
            let hasHealthSession = try await recorder.prepare(record: record)
            record.healthState = hasHealthSession ? .pending : .notRequested
            _ = try await repository.save(record, eventKind: "run.ready")
            activeRun = record
            location.reset()
            try location.start()
            let startedAt = Date()
            try await recorder.start(at: startedAt)
            try record.begin(at: startedAt)
            clock = RunClock(); clock.start(uptime: ProcessInfo.processInfo.systemUptime)
            activeRun = record; displaySeconds = 0
            startTicker()
            try await persist(record, kind: "run.running")
        } catch {
            errorMessage = error.localizedDescription
            if owner == .phone {
                if recorder.state == .running || recorder.state == .paused {
                    // Preserve controls for a real recording even when its checkpoint fails.
                    if activeRun?.phase == .preparing {
                        try? record.begin(at: recorder.currentStartDate ?? Date())
                        activeRun = record
                        clock = RunClock(); clock.start(uptime: ProcessInfo.processInfo.systemUptime)
                    }
                    startTicker()
                    recoveryMessage = t("기록은 진행 중이지만 기기 저장을 다시 확인해야 해요.", "Recording continues, but local saving needs attention.")
                } else {
                    location.stop(); try? await recorder.abortPrepared()
                    record.phase = .interrupted; record.endedAt = Date(); record.revision += 1
                    pendingFinal = record; activeRun = record
                    await retryLocalSave()
                }
            }
        }
    }

    func cancelPreparation() async {
        guard var record = activeRun, record.phase == .preparing, let repository else { return }
        busy = true; defer { busy = false }
        do {
            if record.owner == .watch {
                let message = DeviceMessage(kind: .abort, runID: record.id, revision: record.revision,
                                            expiresAt: Date().addingTimeInterval(20))
                guard let reply = try await link.send(message), reply.kind == .ack, reply.runID == record.id else {
                    throw AppError.unconfirmed
                }
                try link.clearPreparation()
            } else { try await recorder.abortPrepared() }
            record.phase = .interrupted; record.endedAt = Date(); record.revision += 1
            _ = try await repository.save(record, eventKind: "start.aborted")
            activeRun = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func control(_ command: RunCommand) async {
        guard !busy, !pendingControl, let repository else { return }
        busy = true; defer { busy = false }
        if writeInFlight {
            pendingControl = true
            for _ in 0..<100 {
                if !writeInFlight { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            pendingControl = false
        }
        guard !writeInFlight else { errorMessage = AppError.storageBusy.localizedDescription; return }
        guard let record = activeRun else { return }
        do {
            if record.owner == .watch {
                pendingControl = true
                defer { pendingControl = false }
                let request = DeviceMessage(kind: .command, runID: record.id, revision: record.revision,
                                            expiresAt: Date().addingTimeInterval(15), command: command)
                _ = try await repository.save(record, eventKind: "control.requested.\(command.rawValue)")
                guard let reply = try await link.send(request) else { throw AppError.unconfirmed }
                _ = try await receive(reply)
                return
            }
            // The intent keeps the confirmed phase until HealthKit acknowledges it.
            var intent = record
            intent.checkpoint(activeSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
            activeRun = intent
            try await persist(intent, kind: "control.requested.\(command.rawValue)")
            switch command {
            case .pause:
                try await recorder.pause()
                clock.pause(uptime: ProcessInfo.processInfo.systemUptime); location.pause()
            case .resume:
                try await recorder.resume()
                clock.resume(uptime: ProcessInfo.processInfo.systemUptime)
                do { try location.resume() } catch { recoveryMessage = error.localizedDescription }
            case .finish:
                clock.pause(uptime: ProcessInfo.processInfo.systemUptime); location.stop(); stopTicker()
            }
            guard var updated = activeRun, updated.id == record.id else { throw AppError.invalidMessage }
            updated.checkpoint(activeSeconds: clock.elapsed(at: ProcessInfo.processInfo.systemUptime))
            _ = try updated.apply(command, commandID: UUID(), expectedRevision: updated.revision,
                                  expiresAt: Date().addingTimeInterval(15), now: Date())
            activeRun = updated; displaySeconds = updated.activeSeconds
            if command == .finish {
                // Keep the receipt in memory if local save fails, without repeating Health save.
                do { try await persist(updated, kind: "run.ending") }
                catch {
                    var restored = updated
                    restored.phase = recorder.state == .paused ? .paused : .running
                    restored.revision += 1
                    activeRun = restored
                    if restored.phase == .running {
                        clock.resume(uptime: ProcessInfo.processInfo.systemUptime)
                        try? location.resume()
                    }
                    startTicker()
                    throw error
                }
                activeRun = updated
                let outcome = await recorder.finish(at: Date())
                updated.healthState = outcome.workoutState
                updated.healthWorkoutID = outcome.workoutID
                updated.routeState = outcome.routeState
                updated.markSaved(at: Date())
                pendingFinal = updated
                if let error = outcome.errorMessage { recoveryMessage = error }
                await retryLocalSave()
                return
            }
            try await persist(updated, kind: "control.confirmed.\(command.rawValue)")
        } catch {
            errorMessage = error.localizedDescription
            if record.owner == .phone { await reconcileRecorderState() }
        }
    }

    func retryLocalSave() async {
        guard let final = pendingFinal else { return }
        do {
            try await persist(final, kind: "run.saved")
            pendingFinal = nil; canRetrySave = false
            activeRun = nil; summary = final; stopTicker()
            await reloadHistory()
        } catch {
            canRetrySave = true
            errorMessage = t("기기에 저장하지 못했어요. 저장을 다시 시도해 주세요. 건강에 중복 저장하지 않습니다.", "Local saving failed. Retry saving. Health will not be written again.")
        }
    }

    func deleteRun(_ id: UUID) async -> Bool {
        guard id != activeRun?.id, let repository else { return false }
        do { try await repository.delete(id: id); await reloadHistory(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func requestWatchState() async {
        guard let run = activeRun, run.owner == .watch, link.isReachable else { return }
        let request = DeviceMessage(kind: .snapshot, runID: run.id, revision: run.revision,
                                    expiresAt: Date().addingTimeInterval(20))
        do { if let reply = try await link.send(request) { _ = try await receive(reply) } }
        catch { errorMessage = error.localizedDescription }
    }

    private func persist(_ record: RunRecord, kind: String) async throws {
        guard let repository, !writeInFlight else { throw AppError.storageBusy }
        writeInFlight = true; defer { writeInFlight = false }
        let batch = pendingRoute
        _ = try await repository.save(record, routeBatch: batch, eventKind: kind)
        pendingRoute.removeFirst(min(batch.count, pendingRoute.count))
    }

    private func reconcileRecorderState() async {
        guard var run = activeRun, run.owner == .phone, run.phase.isActive,
              pendingFinal == nil else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        switch recorder.state {
        case .paused:
            guard run.phase != .paused else { return }
            clock.pause(uptime: uptime); location.pause(); run.phase = .paused
        case .running:
            guard run.phase != .running else { return }
            clock.resume(uptime: uptime); try? location.resume(); run.phase = .running
        case .ended, .failed:
            clock.pause(uptime: uptime); location.stop(); stopTicker()
            run.phase = .interrupted; run.endedAt = Date()
            if run.healthState == .pending { run.healthState = .uncertain }
        default: return
        }
        run.revision += 1
        run.checkpoint(activeSeconds: clock.elapsed(at: uptime))
        activeRun = run; displaySeconds = run.activeSeconds
        if run.phase == .interrupted { pendingFinal = run; await retryLocalSave() }
        else { do { try await persist(run, kind: "owner.state") } catch { errorMessage = error.localizedDescription } }
    }

    func loadDetail(_ id: UUID) async -> RunRecord? { try? await repository?.load(id: id) }

    private func configureServices() {
        link.onMessage = { [weak self] message in try await self?.receive(message) }
        link.onReachabilityChange = { [weak self] reachable in
            guard reachable, let self, let run = self.activeRun, run.owner == .watch else { return }
            Task { await self.requestWatchState() }
        }
        recorder.onMirrorStarted = { [weak self] in Task { await self?.requestWatchState() } }
        recorder.onStateChange = { [weak self] _, _ in
            guard let self, !self.busy else { return }
            Task { await self.reconcileRecorderState() }
        }
        recorder.onRemoteData = { [weak self] data in
            guard let self, let message = try? JSONDecoder().decode(DeviceMessage.self, from: data) else { return }
            Task { _ = try? await self.receive(message) }
        }
        recorder.onMeasurements = { [weak self] measurements in
            guard let self, var record = self.activeRun, record.owner == .phone else { return }
            record.heartRate = measurements.heartRate
            record.cadence = measurements.cadence
            record.power = measurements.power
            self.activeRun = record
        }
        recorder.onError = { [weak self] error in self?.errorMessage = error.localizedDescription }
        location.onError = { [weak self] error in self?.errorMessage = error.localizedDescription }
        location.onUpdate = { [weak self] update in
            guard let self, var run = self.activeRun, run.phase == .running else { return }
            // This increment uses owner GPS. Phone-to-Watch route transfer is a release gate.
            if run.owner == .phone {
                run.distanceMeters = update.distanceMeters
                if self.pendingRoute.count < 512 { self.pendingRoute.append(update.point) }
                else { self.recoveryMessage = self.t("경로 저장이 지연되어 일부 구간이 빠질 수 있어요.", "Route saving is delayed. Some points may be missing.") }
                self.lastLocationAt = update.point.timestamp
                self.currentPace = update.paceSecondsPerKilometer
                self.recorder.setGPSDistance(update.distanceMeters, at: update.point.timestamp)
                self.recorder.appendLocations([update.location])
                self.activeRun = run
            }
        }
    }

    private func receive(_ message: DeviceMessage) async throws -> DeviceMessage? {
        guard message.schemaVersion == 1, let repository else { throw AppError.invalidMessage }
        if message.kind == .ready {
            guard let record = activeRun, record.id == message.runID, record.owner == .watch,
                  record.phase == .preparing, message.expiresAt > Date() else { throw AppError.invalidMessage }
            if !commitInFlight {
                commitInFlight = true
                let id = commitID ?? UUID(); commitID = id
                do { _ = try await repository.save(record, eventKind: "watch.commit.requested") }
                catch { commitInFlight = false; throw error }
                Task { [weak self] in
                    guard let self else { return }
                    defer { self.commitInFlight = false }
                    do {
                        let commit = DeviceMessage(kind: .commit, runID: record.id, commandID: id,
                                                   revision: record.revision, expiresAt: Date().addingTimeInterval(30), record: record)
                        guard let reply = try await self.link.send(commit) else { throw AppError.unconfirmed }
                        _ = try await self.receive(reply)
                    } catch { self.errorMessage = error.localizedDescription }
                }
            }
            return ack(message)
        }
        guard message.kind == .snapshot, let incoming = message.record, incoming.id == message.runID,
              incoming.owner == .watch, incoming.revision == message.revision else { throw AppError.invalidMessage }
        guard incoming.phase.isFinished || message.expiresAt > Date() else { return ack(message) }
        guard incoming.phase.isFinished || activeRun == nil || activeRun?.id == incoming.id else { throw AppError.invalidMessage }
        let previous = try await repository.load(id: incoming.id)
        if let previous {
            guard incoming.revision >= previous.revision else { return ack(message) }
            guard previous.owner == .watch else { throw AppError.invalidMessage }
        } else if incoming.phase != .saved && incoming.phase != .interrupted {
            throw AppError.invalidMessage
        }
        do {
            guard try await repository.save(incoming, eventID: message.commandID, eventKind: "watch.snapshot") else { return ack(message) }
        } catch RunError.staleSnapshot { return ack(message) }
          catch RunError.deletedRun { return ack(message) }
        if activeRun?.id == incoming.id { lastSnapshotTime = Date() }
        if incoming.phase == .saved || incoming.phase == .interrupted {
            if activeRun?.id == incoming.id { activeRun = nil; location.stop(); stopTicker() }
            if activeRun == nil { summary = incoming }
            await reloadHistory()
        } else {
            guard activeRun == nil || activeRun?.id == incoming.id else { throw AppError.invalidMessage }
            activeRun = incoming; displaySeconds = incoming.activeSeconds
            startTicker()
        }
        return ack(message)
    }

    private func ack(_ message: DeviceMessage) -> DeviceMessage {
        DeviceMessage(kind: .ack, runID: message.runID, commandID: message.commandID,
                      revision: message.revision, expiresAt: Date().addingTimeInterval(30))
    }

    private func startTicker() {
        stopTicker()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, var record = self.activeRun else { break }
                if record.owner == .phone, !self.busy {
                    self.displaySeconds = self.clock.elapsed(at: ProcessInfo.processInfo.systemUptime)
                    record.checkpoint(activeSeconds: self.displaySeconds)
                    self.activeRun = record
                    if Date().timeIntervalSince(self.lastCheckpoint) >= 5, !self.checkpointInFlight, !self.writeInFlight {
                        self.checkpointInFlight = true
                        do {
                            try await self.persist(record, kind: "run.checkpoint")
                            self.lastCheckpoint = Date()
                        } catch { self.errorMessage = error.localizedDescription }
                        self.checkpointInFlight = false
                    }
                } else { self.objectWillChange.send() }
            }
        }
    }

    private func stopTicker() { tickTask?.cancel(); tickTask = nil }

    private func reloadHistory() async {
        do { history = try await repository?.records().filter { $0.phase == .saved || $0.phase == .interrupted } ?? [] }
        catch { errorMessage = error.localizedDescription }
    }

    enum AppError: LocalizedError {
        case watchUnavailable, unconfirmed, invalidMessage, storageBusy
        var errorDescription: String? {
            switch self {
            case .watchUnavailable: "Apple Watch 앱을 연결해 주세요. / Connect the Watch app."
            case .unconfirmed: "워치에서 상태를 확인해 주세요. / Check the workout state on your Watch."
            case .invalidMessage: "운동 상태를 확인할 수 없어요. / Unable to verify the workout state."
            case .storageBusy: "기록 저장 중입니다. 잠시 후 다시 시도해 주세요. / Saving. Please try again shortly."
            }
        }
    }
}
