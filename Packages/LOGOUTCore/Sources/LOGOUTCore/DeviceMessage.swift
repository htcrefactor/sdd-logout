import Foundation

public struct DeviceMessage: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case prepare, ready, commit, snapshot, command, abort, ack }
    public var schemaVersion: Int
    public var kind: Kind
    public var runID: UUID
    public var commandID: UUID
    public var revision: Int
    public var expiresAt: Date
    public var record: RunRecord?
    public var command: RunCommand?

    public init(kind: Kind, runID: UUID, commandID: UUID = UUID(), revision: Int,
                expiresAt: Date, record: RunRecord? = nil, command: RunCommand? = nil) {
        schemaVersion = 1; self.kind = kind; self.runID = runID; self.commandID = commandID
        self.revision = revision; self.expiresAt = expiresAt; self.record = record; self.command = command
    }

    public func validate(for current: RunRecord, now: Date = Date()) throws {
        guard schemaVersion == 1 else { throw RunError.unsupportedSchema }
        guard runID == current.id, record.map({ $0.id == runID && $0.owner == current.owner }) ?? true else {
            throw RunError.wrongRun
        }
        guard now <= expiresAt else { throw RunError.expiredCommand }
        guard revision == current.revision else { throw RunError.staleRevision }
        if let record { try record.validate() }
    }
}
