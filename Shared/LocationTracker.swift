import Combine
import CoreLocation
import Foundation
import LOGOUTCore

struct LocationUpdate {
    let point: RoutePoint
    let location: CLLocation
    let distanceMeters: Double
    let paceSecondsPerKilometer: Double?
    let startsNewSegment: Bool
}

enum LocationTrackingError: LocalizedError {
    case permissionRequired, servicesUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionRequired: return RecordingErrorText.choose("야외 경로를 기록하려면 위치 접근을 허용해 주세요.", "Allow location access to record an outdoor route.")
        case .servicesUnavailable: return RecordingErrorText.choose("위치 서비스를 사용할 수 없어요. 설정에서 확인해 주세요.", "Location Services are unavailable. Check Settings.")
        }
    }
}

/// Receives only real locations. Filtering and segment boundaries live in the tested core.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var isTracking = false
    @Published private(set) var lastError: String?

    var onUpdate: ((LocationUpdate) -> Void)?
    var onError: ((Error) -> Void)?
    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    private let manager: CLLocationManager
    private var accumulator = GPSAccumulator()

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        #if os(iOS)
        manager.pausesLocationUpdatesAutomatically = false
        #endif
    }

    func requestAuthorization() { manager.requestWhenInUseAuthorization() }

    func reset(distanceMeters: Double = 0) {
        accumulator = GPSAccumulator(distanceMeters: distanceMeters)
        lastError = nil
    }

    func start() throws {
        guard CLLocationManager.locationServicesEnabled() else { throw LocationTrackingError.servicesUnavailable }
        guard isAuthorized else { throw LocationTrackingError.permissionRequired }
        guard !isTracking else { return }
        accumulator.breakSegment()
        #if os(iOS)
        // Only enable a declared, legitimate background mode. This avoids a runtime assertion
        // in targets that have not enabled background location in their Info.plist.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        manager.allowsBackgroundLocationUpdates = modes.contains("location")
        manager.showsBackgroundLocationIndicator = true
        #endif
        isTracking = true
        manager.startUpdatingLocation()
    }

    func pause() {
        manager.stopUpdatingLocation()
        isTracking = false
        accumulator.breakSegment()
    }

    func resume() throws { try start() }
    func stop() { pause() }

    private func report(_ error: Error) {
        let localized = RecordingErrorText.localized(error, service: .location)
        lastError = localized.localizedDescription
        onError?(localized)
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = status
            self.accuracyAuthorization = accuracy
            if !self.isAuthorized && self.isTracking {
                self.stop()
                self.report(LocationTrackingError.permissionRequired)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.isTracking else { return }
            let now = Date()
            for location in locations {
                let point = RoutePoint(latitude: location.coordinate.latitude,
                                       longitude: location.coordinate.longitude,
                                       altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                                       horizontalAccuracy: location.horizontalAccuracy,
                                       timestamp: location.timestamp)
                guard let accepted = self.accumulator.ingest(point, now: now) else { continue }
                self.onUpdate?(LocationUpdate(point: accepted.point, location: location,
                                              distanceMeters: accepted.distanceMeters,
                                              paceSecondsPerKilometer: accepted.paceSecondsPerKilometer,
                                              startsNewSegment: accepted.startsNewSegment))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A temporary GPS gap does not end the workout or invent a connecting segment.
            self.accumulator.breakSegment()
            if let clError = error as? CLError, clError.code == .denied { self.stop() }
            self.report(error)
        }
    }
}
