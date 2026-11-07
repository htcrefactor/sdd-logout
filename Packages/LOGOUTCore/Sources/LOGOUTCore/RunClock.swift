import Foundation

/// Process-local timing. Persist elapsed checkpoints, never a monotonic anchor from another boot.
public struct RunClock: Sendable {
    public private(set) var accumulatedSeconds: Double
    public private(set) var anchorUptime: TimeInterval?
    public private(set) var requiresReconciliation = false
    public var isRunning: Bool { anchorUptime != nil }

    public init(activeSeconds: Double = 0) {
        accumulatedSeconds = activeSeconds.isFinite ? max(0, activeSeconds) : 0
    }
    public mutating func start(uptime: TimeInterval) {
        guard anchorUptime == nil, uptime.isFinite, uptime >= 0, !requiresReconciliation else { return }
        anchorUptime = uptime
    }
    public mutating func resume(uptime: TimeInterval) { start(uptime: uptime) }
    public func elapsed(at uptime: TimeInterval) -> Double {
        guard let anchorUptime, uptime.isFinite, uptime >= anchorUptime else { return accumulatedSeconds }
        return accumulatedSeconds + uptime - anchorUptime
    }
    public mutating func checkpoint(uptime: TimeInterval) {
        guard let anchorUptime else { return }
        guard uptime.isFinite, uptime >= anchorUptime else {
            self.anchorUptime = nil
            requiresReconciliation = true
            return
        }
        accumulatedSeconds += uptime - anchorUptime
        self.anchorUptime = uptime
    }
    public mutating func pause(uptime: TimeInterval) {
        checkpoint(uptime: uptime)
        anchorUptime = nil
    }
}
