import Combine
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import LOGOUTCore

enum HealthWriteAuthorization { case unavailable, notDetermined, denied, authorized }
enum RecorderState { case idle, prepared, running, paused, ending, ended, failed }

/// Service errors use the app's language, independently of the device language.
/// Native error descriptions are not exposed because they may be untranslated or contain
/// implementation details. Preserve actionable categories without logging health data.
enum RecordingErrorText {
    enum Service { case health, location, motion }

    static func choose(_ korean: String, _ english: String) -> String {
        #if os(watchOS)
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"
        #else
        let language = UserDefaults.standard.string(forKey: "language") ?? "ko"
        #endif
        return language == "en" ? english : korean
    }

    static func localized(_ error: Error, service: Service = .health) -> Error {
        if error is WorkoutRecorderError || error is LocationTrackingError || error is RecordingServiceFailure { return error }
        if error is CancellationError { return RecordingServiceFailure.cancelled }
        let native = error as NSError
        if native.domain == HKErrorDomain {
            switch HKError.Code(rawValue: native.code) {
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
                return RecordingServiceFailure.healthPermission
            case .errorDatabaseInaccessible: return RecordingServiceFailure.healthLocked
            case .errorAnotherWorkoutSessionStarted: return RecordingServiceFailure.anotherWorkout
            default: return RecordingServiceFailure.health
            }
        }
        if native.domain == kCLErrorDomain {
            switch CLError.Code(rawValue: native.code) {
            case .denied: return LocationTrackingError.permissionRequired
            case .locationUnknown: return RecordingServiceFailure.locationSignal
            default: return RecordingServiceFailure.location
            }
        }
        switch service {
        case .health: return RecordingServiceFailure.health
        case .location: return RecordingServiceFailure.location
        case .motion: return RecordingServiceFailure.motion
        }
    }

    static func message(for error: Error, service: Service = .health) -> String {
        localized(error, service: service).localizedDescription
    }
}

enum RecordingServiceFailure: LocalizedError {
    case health, healthPermission, healthLocked, anotherWorkout, location, locationSignal, motion, cancelled
    var errorDescription: String? {
        switch self {
        case .health: return RecordingErrorText.choose("건강 앱과 연결하지 못했어요. 저장 상태를 확인해 주세요.", "Could not connect to Health. Check the workout save status.")
        case .healthPermission: return RecordingErrorText.choose("이 작업에 필요한 건강 접근이 허용되지 않았어요. 설정에서 권한을 확인해 주세요.", "Health access for this action is unavailable. Check permissions in Settings.")
        case .healthLocked: return RecordingErrorText.choose("기기 잠금을 해제한 뒤 건강 앱 저장 상태를 확인해 주세요.", "Unlock the device, then check the Health save status.")
        case .anotherWorkout: return RecordingErrorText.choose("다른 운동 세션이 시작되어 현재 운동이 중단되었어요. 기록을 확인해 주세요.", "Another workout session interrupted this run. Review the saved record.")
        case .location: return RecordingErrorText.choose("위치를 확인하지 못했어요. 위치 접근과 GPS 상태를 확인해 주세요.", "Location is unavailable. Check location access and the GPS signal.")
        case .locationSignal: return RecordingErrorText.choose("GPS 신호를 찾고 있어요. 위치를 확인할 수 없는 구간은 경로에 추가하지 않아요.", "Searching for GPS. Unavailable locations are not added to the route.")
        case .motion: return RecordingErrorText.choose("걸음 측정을 사용할 수 없어요. 설정에서 동작 및 피트니스 접근을 확인해 주세요.", "Step measurements are unavailable. Check Motion & Fitness access in Settings.")
        case .cancelled: return RecordingErrorText.choose("작업이 취소되었어요. 현재 운동 상태를 확인해 주세요.", "The action was cancelled. Check the current workout state.")
        }
    }
}

struct WorkoutMeasurements {
    var distanceMeters: Double?
    var heartRate: TimedMetric?
    var cadence: TimedMetric?
    var power: TimedMetric?
}

struct HealthFinishResult {
    var workoutID: UUID?
    var workoutState: HealthSaveState
    var routeState: HealthSaveState
    var errorMessage: String?
}

enum WorkoutRecorderError: LocalizedError {
    case healthUnavailable, healthWriteRequired, wrongOwner, alreadyActive, invalidState
    case stateTimeout, sessionFailed, noRemoteSession, routeBufferFull, sampleBufferFull
    case recoveryIdentityMismatch, noWorkoutReturned
    var errorDescription: String? {
        switch self {
        case .healthUnavailable: return RecordingErrorText.choose("이 기기에서는 건강 앱을 사용할 수 없어요.", "Health is unavailable on this device.")
        case .healthWriteRequired: return RecordingErrorText.choose("Apple Watch로 기록하려면 건강 앱에 운동을 쓰도록 허용해 주세요.", "Allow workout writing in Health to record with Apple Watch.")
        case .wrongOwner: return RecordingErrorText.choose("현재 운동을 기록하는 기기에서 조작해 주세요.", "Use the device that owns this recording.")
        case .alreadyActive: return RecordingErrorText.choose("이미 진행 중인 운동이 있어요.", "A workout is already active.")
        case .invalidState: return RecordingErrorText.choose("현재 운동 상태에서는 이 작업을 할 수 없어요.", "The workout cannot perform this action in its current state.")
        case .stateTimeout: return RecordingErrorText.choose("운동 상태 변경을 확인하지 못했어요. 현재 상태를 확인해 주세요.", "The workout did not confirm its state in time. Check its current state.")
        case .sessionFailed: return RecordingErrorText.choose("운동 세션이 중단되었어요.", "The workout session was interrupted.")
        case .noRemoteSession: return RecordingErrorText.choose("다른 기기의 운동과 연결되지 않았어요.", "The companion workout is not connected.")
        case .routeBufferFull: return RecordingErrorText.choose("건강 앱 경로 저장이 지연되고 있어요. 기기에 보관된 경로를 확인해 주세요.", "Health route writing could not keep up. Check the route retained on this device.")
        case .sampleBufferFull: return RecordingErrorText.choose("건강 앱 거리 저장이 지연되고 있어요. 기기에 보관된 거리를 확인해 주세요.", "Health distance writing could not keep up. Check the distance retained on this device.")
        case .recoveryIdentityMismatch: return RecordingErrorText.choose("복구한 건강 앱 운동을 이 기록과 안전하게 연결하지 못했어요.", "The recovered Health workout could not be matched safely.")
        case .noWorkoutReturned: return RecordingErrorText.choose("건강 앱에 운동이 저장되었는지 확인하지 못했어요.", "Health did not confirm the saved workout.")
        }
    }
}

/// One recorder per app process. Only the primary device owns a live builder.
/// Callers persist run state before acknowledging commands and before requesting a save.
@MainActor
final class WorkoutRecorder: NSObject, ObservableObject {
    @Published private(set) var authorization: HealthWriteAuthorization = .notDetermined
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var measurements = WorkoutMeasurements()
    @Published private(set) var lastError: String?

    var onMeasurements: ((WorkoutMeasurements) -> Void)?
    var onStateChange: ((RecorderState, Date) -> Void)?
    var onRemoteData: ((Data) -> Void)?
    var onMirrorStarted: (() -> Void)?
    var onError: ((Error) -> Void)?
    var currentStartDate: Date? { session?.startDate ?? localStartDate }
    // No wall-clock guess after a crash. The owning Health builder supplies elapsed time.
    var elapsedSeconds: Double? { builder?.elapsedTime }

    private let healthStore = HKHealthStore()
    private let pedometer = CMPedometer()
    private var session: HKWorkoutSession?
    private var mirroredSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var activeRunID: UUID?
    private var localOnly = false
    private var localStartDate: Date?
    private var sessionFailure: Error?
    private var collectionStarted = false
    private var finishTask: Task<HealthFinishResult, Never>?
    private var lastGPSDistance = 0.0
    private var lastGPSDate: Date?
    private var pendingLocations: [CLLocation] = []
    private var pendingSamples: [HKQuantitySample] = []
    private var routeTask: Task<Void, Never>?
    private var samplesTask: Task<Void, Never>?
    private var routePointCount = 0
    private var recoveredRouteMayExist = false
    private var routeWriteError: Error?
    private var distanceWriteError: Error?

    private static let runIDMetadataKey = "studio-glhf.logout.runID"
    private static var deviceOwner: RecordingOwner {
        #if os(watchOS)
        .watch
        #else
        .phone
        #endif
    }

    override init() {
        super.init()
        refreshAuthorization()
        #if os(iOS)
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // A mirror never creates a builder or saves a second workout.
                self.mirroredSession = mirrored
                mirrored.delegate = self
                self.onMirrorStarted?()
            }
        }
        #endif
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorization = .unavailable
            throw WorkoutRecorderError.healthUnavailable
        }
        let distance = HKQuantityType(.distanceWalkingRunning)
        let energy = HKQuantityType(.activeEnergyBurned)
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distance, energy]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distance, energy,
                                      HKQuantityType(.heartRate), HKQuantityType(.runningPower)]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            refreshAuthorization()
        } catch {
            refreshAuthorization()
            report(error)
            throw RecordingErrorText.localized(error)
        }
        // A successful prompt is not proof of read authorization. Never infer it here.
    }

    @discardableResult
    func prepare(record: RunRecord) async throws -> Bool {
        guard record.owner == Self.deviceOwner else { throw WorkoutRecorderError.wrongOwner }
        guard state == .idle || state == .ended || state == .failed else { throw WorkoutRecorderError.alreadyActive }
        guard session == nil || session?.state == .ended else { throw WorkoutRecorderError.alreadyActive }
        resetForNewRun(record)
        refreshAuthorization()
        guard authorization == .authorized else {
            #if os(watchOS)
            throw WorkoutRecorderError.healthWriteRequired
            #else
            localOnly = true
            transition(.prepared, at: Date())
            return false
            #endif
        }

        let configuration = Self.runningConfiguration()
        let primary: HKWorkoutSession
        do { primary = try HKWorkoutSession(healthStore: healthStore, configuration: configuration) }
        catch { throw RecordingErrorText.localized(error) }
        let liveBuilder = primary.associatedWorkoutBuilder()
        let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        #if os(iOS)
        // Phone distance is derived only from accepted GPS points. Never add it to the
        // automatic HealthKit distance total.
        source.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
        #endif
        session = primary
        builder = liveBuilder
        primary.delegate = self
        liveBuilder.delegate = self
        liveBuilder.dataSource = source
        primary.prepare()
        do {
            try await awaitState(.prepared, session: primary)
            #if os(watchOS)
            try await primary.startMirroringToCompanionDevice()
            #endif
            return true
        } catch {
            primary.end()
            liveBuilder.discardWorkout()
            try? await awaitState(.ended, session: primary)
            report(error)
            throw RecordingErrorText.localized(error)
        }
    }

    func start(at date: Date = Date()) async throws {
        guard state == .prepared else { throw WorkoutRecorderError.invalidState }
        if localOnly {
            localStartDate = date
            transition(.running, at: date)
            startPedometer(at: date)
            return
        }
        guard let session, let builder, let activeRunID else { throw WorkoutRecorderError.invalidState }
        session.startActivity(with: date)
        do {
            try await builder.beginCollection(at: date)
            collectionStarted = true
            try await builder.addMetadata([
                Self.runIDMetadataKey: activeRunID.uuidString,
                HKMetadataKeySyncIdentifier: "LOGOUT-\(activeRunID.uuidString)",
                HKMetadataKeySyncVersion: 1,
                HKMetadataKeyIndoorWorkout: false
            ])
            if healthStore.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingAuthorized {
                routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
            }
            try await awaitState(.running, session: session)
            lastGPSDate = date
            startPedometer(at: date)
        } catch {
            // The durable journal still owns the interrupted run. Do not silently restart.
            session.end()
            builder.discardWorkout()
            try? await awaitState(.ended, session: session)
            report(error)
            throw RecordingErrorText.localized(error)
        }
    }

    func pause() async throws {
        guard state == .running else { throw WorkoutRecorderError.invalidState }
        pedometer.stopUpdates()
        lastGPSDate = nil
        if localOnly { transition(.paused, at: Date()); return }
        guard let session else { throw WorkoutRecorderError.invalidState }
        session.pause()
        try await awaitState(.paused, session: session)
    }

    func resume() async throws {
        guard state == .paused else { throw WorkoutRecorderError.invalidState }
        if localOnly { transition(.running, at: Date()); startPedometer(at: Date()); return }
        guard let session else { throw WorkoutRecorderError.invalidState }
        session.resume()
        try await awaitState(.running, session: session)
        lastGPSDate = Date()
        startPedometer(at: Date())
    }

    func abortPrepared() async throws {
        guard state == .prepared || state == .idle || state == .failed || state == .ended else {
            throw WorkoutRecorderError.invalidState
        }
        pedometer.stopUpdates()
        if let session, session.state != .ended {
            session.end()
            try await awaitState(.ended, session: session)
        }
        builder?.discardWorkout()
        transition(.ended, at: Date())
    }

    /// Repeated calls share one operation. An ambiguous Health result is never retried here.
    func finish(at date: Date = Date()) async -> HealthFinishResult {
        if let finishTask { return await finishTask.value }
        let task = Task { await self.finishOnce(at: date) }
        finishTask = task
        return await task.value
    }

    private func finishOnce(at date: Date) async -> HealthFinishResult {
        pedometer.stopUpdates()
        if localOnly {
            transition(.ended, at: date)
            return HealthFinishResult(workoutID: nil, workoutState: .notRequested, routeState: .notRequested)
        }
        guard let session, let builder, collectionStarted else {
            session?.end()
            builder?.discardWorkout()
            transition(.ended, at: date)
            return HealthFinishResult(workoutID: nil, workoutState: .notRequested, routeState: .notRequested)
        }
        transition(.ending, at: date)
        defer { session.end() }
        var attemptedSave = false
        do {
            if session.state == .running || session.state == .paused {
                session.stopActivity(with: date)
                try await awaitState(.stopped, session: session)
            }
            // Drain bounded accepted batches before finalizing. Do not finalize a second
            // standalone route; Apple's associated series builder handles it atomically.
            await routeTask?.value
            await samplesTask?.value
            try await builder.endCollection(at: date)
            // Flush final cumulative values before the coordinator creates its summary.
            // Delegate delivery can lag behind endCollection's completion.
            collectStatistics(from: builder, types: [HKQuantityType(.heartRate), HKQuantityType(.runningPower), HKQuantityType(.distanceWalkingRunning)])
            attemptedSave = true
            guard let workout = try await builder.finishWorkout() else { throw WorkoutRecorderError.noWorkoutReturned }
            let routeState: HealthSaveState
            if routeWriteError != nil {
                routeState = .failed
            } else {
                // Empty queries also occur when read permission is withheld. In that case
                // retain pending verification, never claim a save failed and write again.
                let verified = (try? await hasRoute(for: workout)) == true
                routeState = verified ? .saved : ((routePointCount > 0 || recoveredRouteMayExist) ? .pending : .notRequested)
            }
            transition(.ended, at: date)
            return HealthFinishResult(workoutID: workout.uuid, workoutState: .saved, routeState: routeState,
                                      errorMessage: (routeWriteError ?? distanceWriteError).map { RecordingErrorText.message(for: $0) })
        } catch {
            report(error)
            transition(.failed, at: date)
            return HealthFinishResult(workoutID: nil, workoutState: attemptedSave ? .uncertain : .failed,
                                      routeState: routePointCount > 0 ? .uncertain : .notRequested,
                                      errorMessage: RecordingErrorText.message(for: error))
        }
    }

    /// Adopts only a Health primary whose stable identifier matches the durable local journal.
    func recover(record: RunRecord) async throws -> Bool {
        guard record.owner == Self.deviceOwner else { throw WorkoutRecorderError.wrongOwner }
        guard session == nil else { return activeRunID == record.id }
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let recoveredSession: HKWorkoutSession?
        do { recoveredSession = try await healthStore.recoverActiveWorkoutSession() }
        catch { throw RecordingErrorText.localized(error) }
        guard let recovered = recoveredSession else { return false }
        guard recovered.type == .primary else { return false }
        let recoveredBuilder = recovered.associatedWorkoutBuilder()
        guard recoveredBuilder.metadata[Self.runIDMetadataKey] as? String == record.id.uuidString else {
            throw WorkoutRecorderError.recoveryIdentityMismatch
        }
        // Pending while running means a future save is expected. Pending after an end
        // intent, or an uncertain previous save, must be reconciled rather than repeated.
        guard record.phase != .ending && record.healthState != .uncertain && record.healthState != .saved else {
            // Identity is proven, so stop this app's residual session without writing
            // or discarding its potentially completed workout. The caller preserves an
            // unresolved Health status and can reconcile the stable identifier by query.
            recovered.end()
            return false
        }
        resetForNewRun(record)
        session = recovered
        builder = recoveredBuilder
        recovered.delegate = self
        recoveredBuilder.delegate = self
        collectionStarted = recoveredBuilder.startDate != nil
        lastGPSDistance = record.distanceMeters
        routeBuilder = recoveredBuilder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
        routePointCount = record.route.count
        recoveredRouteMayExist = true
        receiveState(recovered.state, at: Date())
        #if os(watchOS)
        do { try await recovered.startMirroringToCompanionDevice() }
        catch { report(error) } // A mirror failure must not orphan a recovered primary.
        #endif
        if recovered.state == .running { startPedometer(at: Date()) }
        collectStatistics(from: recoveredBuilder, types: [HKQuantityType(.heartRate), HKQuantityType(.runningPower), HKQuantityType(.distanceWalkingRunning)])
        return true
    }

    func sendRemote(_ data: Data) async throws {
        // Leave protocol headroom below HealthKit's shared 100 KB / 10 second budget.
        guard data.count <= 48 * 1024 else { throw WorkoutRecorderError.noRemoteSession }
        guard let remote = mirroredSession ?? session, !localOnly else { throw WorkoutRecorderError.noRemoteSession }
        do { try await remote.sendToRemoteWorkoutSession(data: data) }
        catch { throw RecordingErrorText.localized(error) }
    }

    #if os(iOS)
    func launchWatch() async throws {
        do { try await healthStore.startWatchApp(toHandle: Self.runningConfiguration()) }
        catch { throw RecordingErrorText.localized(error) }
    }
    #endif

    func appendLocations(_ locations: [CLLocation]) {
        guard state == .running, !localOnly, routeBuilder != nil, routeWriteError == nil else { return }
        let accepted = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard pendingLocations.count + accepted.count <= 512 else {
            routeWriteError = WorkoutRecorderError.routeBufferFull
            report(WorkoutRecorderError.routeBufferFull)
            return
        }
        pendingLocations.append(contentsOf: accepted)
        guard routeTask == nil else { return }
        routeTask = Task { [weak self] in
            guard let self else { return }
            defer { self.routeTask = nil }
            while !self.pendingLocations.isEmpty, self.routeWriteError == nil {
                let batch = Array(self.pendingLocations.prefix(64))
                self.pendingLocations.removeFirst(batch.count)
                do {
                    try await self.routeBuilder?.insertRouteData(batch)
                    self.routePointCount += batch.count
                } catch {
                    self.routeWriteError = error
                    self.pendingLocations.removeAll()
                    self.report(error)
                }
            }
        }
    }

    func setGPSDistance(_ meters: Double, at date: Date) {
        #if os(iOS)
        guard activeRunID != nil, state == .running, meters.isFinite, meters >= lastGPSDistance else { return }
        let increment = meters - lastGPSDistance
        let start = lastGPSDate
        lastGPSDistance = meters
        lastGPSDate = date
        measurements.distanceMeters = meters
        onMeasurements?(measurements)
        guard !localOnly, collectionStarted, increment > 0, let start, date > start,
              distanceWriteError == nil,
              healthStore.authorizationStatus(for: HKQuantityType(.distanceWalkingRunning)) == .sharingAuthorized else { return }
        guard pendingSamples.count < 128 else {
            distanceWriteError = WorkoutRecorderError.sampleBufferFull
            report(WorkoutRecorderError.sampleBufferFull)
            return
        }
        pendingSamples.append(HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                               quantity: HKQuantity(unit: .meter(), doubleValue: increment),
                                               start: start, end: date))
        guard samplesTask == nil else { return }
        samplesTask = Task { [weak self] in
            guard let self else { return }
            defer { self.samplesTask = nil }
            while !self.pendingSamples.isEmpty, self.distanceWriteError == nil {
                let batch = Array(self.pendingSamples.prefix(32))
                self.pendingSamples.removeFirst(batch.count)
                do { try await self.builder?.addSamples(batch) }
                catch {
                    self.distanceWriteError = error
                    self.pendingSamples.removeAll()
                    self.report(error)
                }
            }
        }
        #endif
    }

    private func refreshAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { authorization = .unavailable; return }
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: authorization = .authorized
        case .sharingDenied: authorization = .denied
        case .notDetermined: authorization = .notDetermined
        @unknown default: authorization = .notDetermined
        }
    }

    private static func runningConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        return configuration
    }

    private func resetForNewRun(_ record: RunRecord) {
        activeRunID = record.id
        session = nil
        builder = nil
        routeBuilder = nil
        localOnly = false
        localStartDate = nil
        collectionStarted = false
        sessionFailure = nil
        finishTask = nil
        measurements = WorkoutMeasurements()
        lastError = nil
        lastGPSDistance = record.distanceMeters
        lastGPSDate = nil
        pendingLocations = []
        pendingSamples = []
        routePointCount = 0
        recoveredRouteMayExist = false
        routeWriteError = nil
        distanceWriteError = nil
    }

    private func awaitState(_ expected: HKWorkoutSessionState, session: HKWorkoutSession) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while session.state != expected {
            if let sessionFailure { throw RecordingErrorText.localized(sessionFailure) }
            if session.state == .ended && expected != .ended { throw WorkoutRecorderError.sessionFailed }
            guard ContinuousClock.now < deadline else { throw WorkoutRecorderError.stateTimeout }
            try await Task.sleep(for: .milliseconds(50))
        }
        // The delegate may be queued behind this actor; expose the actual confirmed state now.
        receiveState(expected, at: Date())
    }

    private func transition(_ newState: RecorderState, at date: Date) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState, date)
    }

    private func receiveState(_ hkState: HKWorkoutSessionState, at date: Date) {
        switch hkState {
        case .notStarted: break
        case .prepared: transition(.prepared, at: date)
        case .running: transition(.running, at: date)
        case .paused: transition(.paused, at: date)
        case .stopped: transition(.ending, at: date)
        case .ended: transition(.ended, at: date)
        @unknown default: break
        }
    }

    private func report(_ error: Error) {
        let localized = RecordingErrorText.localized(error)
        lastError = localized.localizedDescription
        onError?(localized)
    }

    private func startPedometer(at date: Date) {
        guard CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: date) { [weak self] data, error in
            // Snapshot the actual measurement timestamp before hopping queues.
            let cadence = data?.currentCadence?.doubleValue
            let observedAt = data?.endDate
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                if let error { self.report(RecordingErrorText.localized(error, service: .motion)); return }
                guard let cadence, let observedAt, cadence.isFinite, cadence >= 0 else { return }
                self.measurements.cadence = TimedMetric(value: cadence * 60, observedAt: observedAt,
                                                       source: Self.deviceOwner)
                self.onMeasurements?(self.measurements)
            }
        }
    }

    private func collectStatistics(from builder: HKLiveWorkoutBuilder, types: Set<HKSampleType>) {
        guard state == .running || state == .paused || state == .ending else { return }
        for type in types {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = builder.statistics(for: quantityType) else { continue }
            if quantityType == HKQuantityType(.distanceWalkingRunning) {
                #if os(watchOS)
                if let value = statistics.sumQuantity()?.doubleValue(for: .meter()), value.isFinite, value >= 0 {
                    measurements.distanceMeters = value
                }
                #endif
                continue
            }
            guard let observedAt = statistics.mostRecentQuantityDateInterval()?.end,
                  let quantity = statistics.mostRecentQuantity() else { continue }
            if quantityType == HKQuantityType(.heartRate) {
                let value = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                if value.isFinite, value > 0 {
                    measurements.heartRate = TimedMetric(value: value, observedAt: observedAt, source: Self.deviceOwner)
                }
            } else if quantityType == HKQuantityType(.runningPower) {
                let value = quantity.doubleValue(for: .watt())
                if value.isFinite, value >= 0 {
                    measurements.power = TimedMetric(value: value, observedAt: observedAt, source: Self.deviceOwner)
                }
            }
        }
        onMeasurements?(measurements)
    }

    private func hasRoute(for workout: HKWorkout) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(),
                                      predicate: HKQuery.predicateForObjects(from: workout),
                                      limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: !(samples ?? []).isEmpty) }
            }
            healthStore.execute(query)
        }
    }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                   from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Mirrored state is informative; the coordinator accepts only owner protocol
            // snapshots for the logical run, so it must not overwrite a local primary.
            if self.session === workoutSession, workoutSession.state == toState {
                self.receiveState(toState, at: date)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.session === workoutSession {
                self.sessionFailure = error
                self.pedometer.stopUpdates()
                self.transition(.failed, at: Date())
            }
            self.report(error)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor [weak self] in
            for payload in data where payload.count <= 48 * 1024 { self?.onRemoteData?(payload) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor [weak self] in
            // A lost link never ends the primary workout. Samples keep their original age.
            if let error { self?.report(error) }
        }
    }
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor [weak self] in
            guard let self, self.builder === workoutBuilder else { return }
            self.collectStatistics(from: workoutBuilder, types: collectedTypes)
        }
    }
}
