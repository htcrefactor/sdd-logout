import Foundation
@preconcurrency import CoreData

public struct RunJournalEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let sequence: Int
    public let kind: String
    public let recordedAt: Date
    public let record: RunRecord?

    public init(id: UUID, runID: UUID, sequence: Int, kind: String, recordedAt: Date, record: RunRecord?) {
        self.id = id; self.runID = runID; self.sequence = sequence
        self.kind = kind; self.recordedAt = recordedAt; self.record = record
    }
}

/// All writes are serialized. A saved snapshot, its journal entry and new route chunks commit together.
/// A successful return is the application's durability boundary before sending an acknowledgement.
public actor RunRepository {
    private let context: NSManagedObjectContext
    private let coordinator: NSPersistentStoreCoordinator
    public nonisolated let storeURL: URL?

    public init(directory: URL? = nil, inMemory: Bool = false) throws {
        let model = Self.makeModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        var options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSSQLitePragmasOption: ["journal_mode": "WAL", "synchronous": "FULL"]
        ]
        var url: URL?
        if !inMemory {
            var folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                               in: .userDomainMask)[0]
                .appendingPathComponent("LOGOUTRecordings", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            #if os(iOS) || os(watchOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                  ofItemAtPath: folder.path)
            options[NSPersistentStoreFileProtectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            url = folder.appendingPathComponent("Runs-v1.sqlite")
        }
        try coordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType,
                                           configurationName: nil, at: url, options: options)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergePolicy.error
        context.undoManager = nil
        self.coordinator = coordinator
        self.context = context
        storeURL = url
    }

    @discardableResult
    public func save(_ record: RunRecord, routeBatch: [RoutePoint]? = nil,
                     eventID: UUID = UUID(), eventKind: String) async throws -> Bool {
        try record.validate()
        let context = context
        return try context.performAndWait {
            do {
                if let event = try Self.find("RunEvent", id: eventID, in: context) {
                    guard event.value(forKey: "runID") as? String == record.id.uuidString else { throw RunError.eventConflict }
                    return false
                }
                guard try Self.find("RunDeletion", id: record.id, in: context) == nil else { throw RunError.deletedRun }
                let existing = try Self.find("RunSnapshot", id: record.id, in: context)
                let snapshot = existing ?? NSEntityDescription.insertNewObject(forEntityName: "RunSnapshot", into: context)
                var routeCount = 0
                if let existing {
                    let previous = try Self.decode(existing.value(forKey: "payload") as? Data)
                    guard previous.owner == record.owner else { throw RunError.wrongRun }
                    guard record.revision >= previous.revision,
                          record.activeSeconds >= previous.activeSeconds,
                          record.distanceMeters >= previous.distanceMeters else { throw RunError.staleSnapshot }
                    guard record.revision != previous.revision || record.phase == previous.phase,
                          previous.healthState != .saved || record.healthState == .saved,
                          previous.routeState != .saved || record.routeState == .saved,
                          previous.healthWorkoutID == nil || previous.healthWorkoutID == record.healthWorkoutID else {
                        throw RunError.staleSnapshot
                    }
                    switch previous.phase {
                    case .saved:
                        guard record.phase == .saved else { throw RunError.staleSnapshot }
                    case .ending, .interrupted:
                        guard [.ending, .interrupted, .saved].contains(record.phase) else { throw RunError.staleSnapshot }
                    default: break
                    }
                    routeCount = (existing.value(forKey: "routeCount") as? NSNumber)?.intValue ?? 0
                }
                if let routeBatch {
                    // Choose either an incremental batch or a cumulative route for one write.
                    guard record.route.isEmpty else { throw RunError.eventConflict }
                    try Self.validateRoute(routeBatch)
                    if let first = routeBatch.first,
                       let previousPoint = try Self.lastRoutePoint(for: record.id, in: context),
                       first.timestamp <= previousPoint.timestamp { throw RunError.eventConflict }
                    try Self.insertRoute(routeBatch, runID: record.id, in: context)
                    routeCount += routeBatch.count
                } else if record.route.count > routeCount {
                    let newPoints = Array(record.route.dropFirst(routeCount))
                    try Self.validateRoute(newPoints)
                    if routeCount > 0 {
                        guard let previousPoint = try Self.lastRoutePoint(for: record.id, in: context),
                              previousPoint == record.route[routeCount - 1],
                              newPoints[0].timestamp > previousPoint.timestamp else { throw RunError.eventConflict }
                    }
                    try Self.insertRoute(newPoints, runID: record.id, in: context)
                    routeCount = record.route.count
                }
                var lightweight = record
                lightweight.route = []
                let payload = try Self.encoder().encode(lightweight)
                snapshot.setValue(record.id.uuidString, forKey: "id")
                snapshot.setValue(record.phase.rawValue, forKey: "phase")
                snapshot.setValue(record.revision, forKey: "revision")
                snapshot.setValue(Date(), forKey: "updatedAt")
                snapshot.setValue(payload, forKey: "payload")
                snapshot.setValue(routeCount, forKey: "routeCount")
                try Self.insertEvent(id: eventID, runID: record.id, kind: eventKind, payload: payload, in: context)
                try context.save()
                return true
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// The list deliberately omits routes. Open one record with load(id:) to read its route.
    public func records() async throws -> [RunRecord] {
        let context = context
        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "RunSnapshot")
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return try context.fetch(request).map { try Self.decode($0.value(forKey: "payload") as? Data) }
        }
    }

    public func load(id: UUID) async throws -> RunRecord? {
        let context = context
        return try context.performAndWait {
            guard let snapshot = try Self.find("RunSnapshot", id: id, in: context) else { return nil }
            var record = try Self.decode(snapshot.value(forKey: "payload") as? Data)
            record.route = try Self.route(for: id, in: context)
            return record
        }
    }

    public func unfinished() async throws -> [RunRecord] {
        try await records().filter { $0.phase != .saved && $0.phase != .interrupted }
    }

    /// An idempotent route-batch API for services that avoid keeping the entire active route in memory.
    @discardableResult
    public func appendRoute(_ points: [RoutePoint], to runID: UUID, batchID: UUID = UUID()) async throws -> Bool {
        guard !points.isEmpty else { return false }
        try Self.validateRoute(points)
        let context = context
        return try context.performAndWait {
            do {
                if let event = try Self.find("RunEvent", id: batchID, in: context) {
                    guard event.value(forKey: "runID") as? String == runID.uuidString else { throw RunError.eventConflict }
                    return false
                }
                guard try Self.find("RunDeletion", id: runID, in: context) == nil else { throw RunError.deletedRun }
                guard let snapshot = try Self.find("RunSnapshot", id: runID, in: context) else { throw RunError.wrongRun }
                let priorCount = (snapshot.value(forKey: "routeCount") as? NSNumber)?.intValue ?? 0
                if let last = try Self.lastRoutePoint(for: runID, in: context),
                   let first = points.first, first.timestamp <= last.timestamp {
                    throw RunError.eventConflict
                }
                try Self.insertRoute(points, runID: runID, in: context)
                snapshot.setValue(priorCount + points.count, forKey: "routeCount")
                try Self.insertEvent(id: batchID, runID: runID, kind: "route.batch", payload: nil, in: context)
                try context.save()
                return true
            } catch { context.rollback(); throw error }
        }
    }

    /// Tombstones prevent a delayed companion snapshot from silently restoring a deleted run.
    public func delete(id: UUID) async throws {
        let context = context
        try context.performAndWait {
            do {
                if try Self.find("RunDeletion", id: id, in: context) != nil { return }
                for name in ["RunSnapshot", "RunRouteChunk", "RunEvent"] {
                    let request = NSFetchRequest<NSManagedObject>(entityName: name)
                    request.predicate = NSPredicate(format: "%K == %@", name == "RunSnapshot" ? "id" : "runID", id.uuidString)
                    for object in try context.fetch(request) { context.delete(object) }
                }
                let tombstone = NSEntityDescription.insertNewObject(forEntityName: "RunDeletion", into: context)
                tombstone.setValue(id.uuidString, forKey: "id")
                tombstone.setValue(Date(), forKey: "deletedAt")
                try context.save()
            } catch { context.rollback(); throw error }
        }
    }

    public func journalEvents(for runID: UUID) async throws -> [RunJournalEvent] {
        let context = context
        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "RunEvent")
            request.predicate = NSPredicate(format: "runID == %@", runID.uuidString)
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
            return try context.fetch(request).map { event in
                guard let rawID = event.value(forKey: "id") as? String, let id = UUID(uuidString: rawID),
                      let kind = event.value(forKey: "kind") as? String,
                      let date = event.value(forKey: "recordedAt") as? Date else { throw RunError.corruptRecord }
                return RunJournalEvent(id: id, runID: runID,
                                       sequence: (event.value(forKey: "sequence") as? NSNumber)?.intValue ?? 0,
                                       kind: kind, recordedAt: date,
                                       record: try (event.value(forKey: "payload") as? Data).map { try Self.decode($0) })
            }
        }
    }

    public func replay(id: UUID) async throws -> RunRecord? {
        let context = context
        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "RunEvent")
            request.predicate = NSPredicate(format: "runID == %@ AND payload != nil", id.uuidString)
            request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
            request.fetchLimit = 1
            guard let event = try context.fetch(request).first else { return nil }
            var last = try Self.decode(event.value(forKey: "payload") as? Data)
            last.route = try Self.route(for: id, in: context)
            return last
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970; return encoder
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder
    }
    private static func decode(_ data: Data?) throws -> RunRecord {
        guard let data else { throw RunError.corruptRecord }
        do {
            let record = try decoder().decode(RunRecord.self, from: data)
            try record.validate()
            return record
        } catch { throw RunError.corruptRecord }
    }
    private static func find(_ entity: String, id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id.uuidString)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    private static func insertEvent(id: UUID, runID: UUID, kind: String, payload: Data?, in context: NSManagedObjectContext) throws {
        let countRequest = NSFetchRequest<NSManagedObject>(entityName: "RunEvent")
        countRequest.predicate = NSPredicate(format: "runID == %@", runID.uuidString)
        let sequence = try context.count(for: countRequest)
        let event = NSEntityDescription.insertNewObject(forEntityName: "RunEvent", into: context)
        event.setValue(id.uuidString, forKey: "id"); event.setValue(runID.uuidString, forKey: "runID")
        event.setValue(kind, forKey: "kind"); event.setValue(sequence, forKey: "sequence")
        event.setValue(Date(), forKey: "recordedAt"); event.setValue(payload, forKey: "payload")
    }
    private static func insertRoute(_ points: [RoutePoint], runID: UUID, in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "RunRouteChunk")
        request.predicate = NSPredicate(format: "runID == %@", runID.uuidString)
        var index = try context.count(for: request)
        for start in stride(from: 0, to: points.count, by: 256) {
            let chunk = NSEntityDescription.insertNewObject(forEntityName: "RunRouteChunk", into: context)
            chunk.setValue(UUID().uuidString, forKey: "id"); chunk.setValue(runID.uuidString, forKey: "runID")
            chunk.setValue(index, forKey: "sequence")
            chunk.setValue(try encoder().encode(Array(points[start..<min(start + 256, points.count)])), forKey: "payload")
            index += 1
        }
    }
    private static func route(for runID: UUID, in context: NSManagedObjectContext) throws -> [RoutePoint] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "RunRouteChunk")
        request.predicate = NSPredicate(format: "runID == %@", runID.uuidString)
        request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: true)]
        return try context.fetch(request).flatMap { chunk in
            guard let data = chunk.value(forKey: "payload") as? Data else { throw RunError.corruptRecord }
            return try decoder().decode([RoutePoint].self, from: data)
        }
    }
    private static func lastRoutePoint(for runID: UUID, in context: NSManagedObjectContext) throws -> RoutePoint? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "RunRouteChunk")
        request.predicate = NSPredicate(format: "runID == %@", runID.uuidString)
        request.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
        request.fetchLimit = 1
        guard let chunk = try context.fetch(request).first else { return nil }
        guard let data = chunk.value(forKey: "payload") as? Data else { throw RunError.corruptRecord }
        return try decoder().decode([RoutePoint].self, from: data).last
    }
    private static func validateRoute(_ points: [RoutePoint]) throws {
        for (index, point) in points.enumerated() {
            guard point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
                  point.horizontalAccuracy.isFinite, point.horizontalAccuracy >= 0,
                  point.altitude.map(\.isFinite) ?? true,
                  index == 0 || point.timestamp > points[index - 1].timestamp else { throw RunError.invalidMeasurement }
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name; attribute.attributeType = type; attribute.isOptional = optional
            return attribute
        }
        func entity(_ name: String, _ properties: [NSAttributeDescription]) -> NSEntityDescription {
            let entity = NSEntityDescription()
            entity.name = name; entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = properties
            entity.uniquenessConstraints = [["id"]]
            return entity
        }
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["LOGOUTCore.v1"]
        model.entities = [
            entity("RunSnapshot", [attribute("id", .stringAttributeType), attribute("phase", .stringAttributeType),
                attribute("revision", .integer64AttributeType), attribute("updatedAt", .dateAttributeType),
                attribute("payload", .binaryDataAttributeType), attribute("routeCount", .integer64AttributeType)]),
            entity("RunEvent", [attribute("id", .stringAttributeType), attribute("runID", .stringAttributeType),
                attribute("sequence", .integer64AttributeType), attribute("kind", .stringAttributeType),
                attribute("recordedAt", .dateAttributeType), attribute("payload", .binaryDataAttributeType, optional: true)]),
            entity("RunRouteChunk", [attribute("id", .stringAttributeType), attribute("runID", .stringAttributeType),
                attribute("sequence", .integer64AttributeType), attribute("payload", .binaryDataAttributeType)]),
            entity("RunDeletion", [attribute("id", .stringAttributeType), attribute("deletedAt", .dateAttributeType)])
        ]
        return model
    }
}
