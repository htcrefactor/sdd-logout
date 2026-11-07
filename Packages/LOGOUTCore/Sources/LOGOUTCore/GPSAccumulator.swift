import Foundation

public struct GPSUpdate: Sendable, Equatable {
    public let point: RoutePoint
    public let distanceMeters: Double
    public let incrementMeters: Double
    public let paceSecondsPerKilometer: Double?
    public let startsNewSegment: Bool

    public init(point: RoutePoint, distanceMeters: Double, incrementMeters: Double,
                paceSecondsPerKilometer: Double?, startsNewSegment: Bool) {
        self.point = point; self.distanceMeters = distanceMeters; self.incrementMeters = incrementMeters
        self.paceSecondsPerKilometer = paceSecondsPerKilometer; self.startsNewSegment = startsNewSegment
    }
}

/// Conservative location acceptance. Gaps are represented as gaps, never straight-line distance.
public struct GPSAccumulator: Sendable {
    public private(set) var distanceMeters: Double
    public private(set) var lastAcceptedPoint: RoutePoint?
    private var window: [(time: Date, distance: Double)] = []
    public var maximumAccuracy: Double = 50
    public var maximumSpeed: Double = 12
    public var maximumAge: Double = 15
    public var maximumGap: Double = 15

    public init(distanceMeters: Double = 0) {
        self.distanceMeters = distanceMeters.isFinite ? max(0, distanceMeters) : 0
    }

    public mutating func breakSegment() {
        lastAcceptedPoint = nil
        window.removeAll(keepingCapacity: true)
    }

    public mutating func ingest(_ point: RoutePoint, now: Date = Date()) -> GPSUpdate? {
        let age = now.timeIntervalSince(point.timestamp)
        guard point.latitude.isFinite, point.longitude.isFinite,
              (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
              point.horizontalAccuracy.isFinite, point.horizontalAccuracy >= 0,
              point.horizontalAccuracy <= maximumAccuracy, age >= 0, age <= maximumAge,
              point.altitude.map(\.isFinite) ?? true else { return nil }

        var increment = 0.0
        var newSegment = lastAcceptedPoint == nil
        if let previous = lastAcceptedPoint {
            let delta = point.timestamp.timeIntervalSince(previous.timestamp)
            guard delta > 0 else { return nil }
            if delta > maximumGap {
                breakSegment()
                newSegment = true
            } else {
                let distance = Self.distance(from: previous, to: point)
                guard distance / delta <= maximumSpeed else { return nil }
                increment = distance
            }
        }
        distanceMeters += increment
        lastAcceptedPoint = point
        window.append((point.timestamp, distanceMeters))
        window.removeAll { point.timestamp.timeIntervalSince($0.time) > 12 }
        var pace: Double?
        if let first = window.first {
            let seconds = point.timestamp.timeIntervalSince(first.time)
            let meters = distanceMeters - first.distance
            if seconds >= 5 && meters >= 3 { pace = seconds / meters * 1_000 }
        }
        return GPSUpdate(point: point, distanceMeters: distanceMeters, incrementMeters: increment,
                         paceSecondsPerKilometer: pace, startsNewSegment: newSegment)
    }

    public static func distance(from a: RoutePoint, to b: RoutePoint) -> Double {
        let radians = Double.pi / 180
        let lat1 = a.latitude * radians, lat2 = b.latitude * radians
        let dLat = (b.latitude - a.latitude) * radians, dLon = (b.longitude - a.longitude) * radians
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(max(0, h)), sqrt(max(0, 1 - h)))
    }
}
