import Combine
import Foundation
import WatchConnectivity
import LOGOUTCore

/// Transport only. The receiving coordinator must validate the run and persist
/// an accepted operation before returning an acknowledgement.
@MainActor
final class DeviceLink: NSObject, ObservableObject {
    @Published private(set) var isReachable = false
    @Published private(set) var isActivated = false
    @Published private(set) var isCompanionInstalled = false
    @Published private(set) var lastError: String?

    var onMessage: ((DeviceMessage) async throws -> DeviceMessage?)?
    var onReachabilityChange: ((Bool) -> Void)?
    var onCompletedReceipt: ((UUID) -> Void)?
    var onLanguageChange: ((AppLanguage) -> Void)?

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let outbox: URL
    private var preparingContextID: UUID?
    private var pendingLanguage: AppLanguage?
    private static let immediateLimit = 48 * 1024
    private static let fileLimit = 16 * 1024 * 1024

    enum LinkError: LocalizedError {
        case unavailable, disconnected, oversized, invalidPayload, storage, rejected(String)
        var errorDescription: String? {
            switch self {
            case .unavailable:
                return Self.choose("기기 간 연결을 사용할 수 없어요. iPhone과 Watch 앱을 열어 연결을 확인해 주세요.", "The companion connection is unavailable. Open the iPhone and Watch apps to check the connection.")
            case .disconnected:
                return Self.choose("다른 기기의 응답을 받지 못했어요. 연결과 현재 운동 상태를 확인한 뒤 다시 시도해 주세요.", "The other device did not respond. Check the connection and current workout state before retrying.")
            case .oversized:
                return Self.choose("이 기록을 한 번에 전달하지 못했어요. 두 기기의 기록 상태를 확인해 주세요.", "This recording could not be transferred in one message. Check the saved records on both devices.")
            case .invalidPayload:
                return Self.choose("전달받은 운동 상태를 확인하지 못했어요. 두 기기의 앱을 업데이트하고 다시 연결해 주세요.", "The received workout state could not be verified. Update both apps and reconnect.")
            case .storage:
                return Self.choose("동기화 기록을 저장하지 못했어요. 기기 저장 공간을 확인한 뒤 다시 시도해 주세요.", "The sync record could not be saved. Check device storage and retry.")
            case .rejected:
                // A peer's free-form error is untrusted and may be in another
                // language or contain implementation details. Show local copy.
                return Self.choose("다른 기기에서 변경을 확인하지 못했어요. 현재 운동 상태를 확인한 뒤 다시 시도해 주세요.", "The other device could not confirm the change. Check the current workout state before retrying.")
            }
        }

        private nonisolated static func choose(_ korean: String, _ english: String) -> String {
            #if os(watchOS)
            let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "ko"
            #else
            let language = UserDefaults.standard.string(forKey: "language") ?? "ko"
            #endif
            return language == "en" ? english : korean
        }
    }

    private struct Reply: Codable {
        var message: DeviceMessage?
        var error: String?
    }

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        outbox = support.appendingPathComponent("LOGOUTTransferOutbox", isDirectory: true)
        super.init()
        session?.delegate = self
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            var directory = outbox
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: outbox.path)
        } catch {
            lastError = Self.message(for: error, fallback: .storage)
        }
    }

    func activate() {
        session?.activate()
        refreshState()
    }

    /// Interactive commands deliberately never fall back to queued delivery.
    func send(_ message: DeviceMessage) async throws -> DeviceMessage? {
        guard let session, isActivated else { throw LinkError.unavailable }
        guard session.isReachable else { throw LinkError.disconnected }
        let data = try encode(message)
        guard data.count <= Self.immediateLimit else { throw LinkError.oversized }
        let replyData: Data
        do {
            replyData = try await withCheckedThrowingContinuation { continuation in
                session.sendMessageData(data, replyHandler: { data in
                    continuation.resume(returning: data)
                }, errorHandler: { _ in
                    continuation.resume(throwing: LinkError.disconnected)
                })
            }
        } catch {
            throw LinkError.disconnected
        }
        guard replyData.count <= Self.immediateLimit else { throw LinkError.oversized }
        let reply: Reply
        do { reply = try decoder.decode(Reply.self, from: replyData) }
        catch { throw LinkError.invalidPayload }
        if let error = reply.error { throw LinkError.rejected(error) }
        return reply.message
    }

    /// Staging can wake with the Watch. Expired preparations must be rejected by
    /// the coordinator, and a staged preparation can never authorize a start.
    func stagePreparation(_ message: DeviceMessage) throws {
        guard message.kind == .prepare, message.schemaVersion == 1 else { throw LinkError.invalidPayload }
        guard let session, isActivated else { throw LinkError.unavailable }
        let data = try encode(message)
        guard data.count <= Self.immediateLimit else { throw LinkError.oversized }
        var context = session.applicationContext
        context["preparation"] = data
        if let language = message.record?.language { context["language"] = language.rawValue }
        do { try session.updateApplicationContext(context) }
        catch { throw LinkError.unavailable }
    }

    func clearPreparation() throws {
        guard let session, isActivated else { return }
        var context = session.applicationContext
        context.removeValue(forKey: "preparation")
        do { try session.updateApplicationContext(context) }
        catch { throw LinkError.unavailable }
    }

    /// Preferences can wait for activation. This never queues workout controls.
    func syncLanguage(_ language: AppLanguage) {
        pendingLanguage = language
        guard let session, isActivated else { return }
        var context = session.applicationContext
        context["language"] = language.rawValue
        do {
            try session.updateApplicationContext(context)
            pendingLanguage = nil
        } catch { lastError = Self.message(for: error) }
    }

    /// The file is retained until the receiver has durably saved the run and
    /// returned a matching application acknowledgement, not merely delivered.
    func queueCompleted(_ record: RunRecord) throws {
        guard record.phase == .saved || record.phase == .interrupted else { throw LinkError.invalidPayload }
        let message = DeviceMessage(kind: .snapshot, runID: record.id, revision: record.revision,
                                    expiresAt: .distantFuture, record: record)
        let data = try encode(message)
        guard data.count <= Self.fileLimit else { throw LinkError.oversized }
        let identifier = "\(record.id.uuidString)-\(record.revision)"
        let url = outbox.appendingPathComponent(identifier).appendingPathExtension("json")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var protectedURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedURL.setResourceValues(values)
        } catch { throw LinkError.storage }
        retryPendingTransfers()
    }

    func retryPendingTransfers() {
        guard let session, isActivated else { return }
        let existing = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?["outboxID"] as? String })
        do {
            for url in try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
                let identifier = url.deletingPathExtension().lastPathComponent
                guard !existing.contains(identifier) else { continue }
                session.transferFile(url, metadata: ["logoutSchema": 1, "outboxID": identifier])
            }
        } catch { lastError = Self.message(for: error, fallback: .storage) }
    }

    func processStagedPreparation() {
        if let raw = session?.receivedApplicationContext["language"] as? String { receiveLanguage(raw) }
        guard let data = session?.receivedApplicationContext["preparation"] as? Data else { return }
        Task { await receivePreparation(data) }
    }

    private func receiveLanguage(_ raw: String) {
        guard let language = AppLanguage(rawValue: raw) else { return }
        onLanguageChange?(language)
    }

    private func encode(_ message: DeviceMessage) throws -> Data {
        do { return try encoder.encode(message) }
        catch { throw LinkError.invalidPayload }
    }

    private static func message(for error: Error, fallback: LinkError = .unavailable) -> String {
        (error as? LinkError ?? fallback).localizedDescription
    }

    private func refreshState() {
        guard let session else { return }
        let previous = isReachable
        isActivated = session.activationState == .activated
        isReachable = session.isReachable
        #if os(iOS)
        isCompanionInstalled = session.isPaired && session.isWatchAppInstalled
        #else
        isCompanionInstalled = session.isCompanionAppInstalled
        #endif
        if previous != isReachable { onReachabilityChange?(isReachable) }
    }

    private func receive(_ data: Data) async -> Data {
        do {
            guard data.count <= Self.immediateLimit else { throw LinkError.oversized }
            let message = try decoder.decode(DeviceMessage.self, from: data)
            guard message.schemaVersion == 1 else { throw LinkError.invalidPayload }
            guard let onMessage else { throw LinkError.unavailable }
            let response = try await onMessage(message)
            return try encoder.encode(Reply(message: response))
        } catch {
            lastError = Self.message(for: error, fallback: .rejected("rejected"))
            return (try? encoder.encode(Reply(error: "rejected"))) ?? Data()
        }
    }

    private func receivePreparation(_ data: Data) async {
        do {
            guard data.count <= Self.immediateLimit else { throw LinkError.oversized }
            let message = try decoder.decode(DeviceMessage.self, from: data)
            guard message.kind == .prepare, message.schemaVersion == 1,
                  message.expiresAt > Date(), preparingContextID != message.commandID else { return }
            guard let onMessage else { return }
            preparingContextID = message.commandID
            if let response = try await onMessage(message), isReachable {
                _ = try? await send(response)
            }
        } catch {
            preparingContextID = nil
            lastError = Self.message(for: error, fallback: .rejected("rejected"))
        }
    }

    private func receiveFile(_ data: Data, identifier: String) async {
        do {
            guard data.count <= Self.fileLimit else { throw LinkError.oversized }
            let message = try decoder.decode(DeviceMessage.self, from: data)
            guard message.schemaVersion == 1, message.kind == .snapshot,
                  let record = message.record, record.id == message.runID,
                  record.phase == .saved || record.phase == .interrupted,
                  let onMessage else { throw LinkError.invalidPayload }
            let reply = try await onMessage(message)
            guard reply?.kind == .ack, reply?.runID == record.id else { return }
            session?.transferUserInfo(["logoutReceipt": identifier, "runID": record.id.uuidString])
        } catch { lastError = Self.message(for: error, fallback: .rejected("rejected")) }
    }

    private func receiveReceipt(identifier: String, runID: String) {
        guard let runID = UUID(uuidString: runID),
              identifier.hasPrefix(runID.uuidString + "-"),
              !identifier.contains("/"), !identifier.contains("..") else { return }
        let url = outbox.appendingPathComponent(identifier).appendingPathExtension("json")
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
            let remaining = try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)
            if !remaining.contains(where: { $0.lastPathComponent.hasPrefix(runID.uuidString + "-") }) {
                onCompletedReceipt?(runID)
            }
        } catch { lastError = Self.message(for: error, fallback: .storage) }
    }
}

extension DeviceLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshState()
            if let error { self.lastError = Self.message(for: error) }
            if let language = self.pendingLanguage { self.syncLanguage(language) }
            self.processStagedPreparation()
            self.retryPendingTransfers()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshState()
            self.retryPendingTransfers()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        Task { @MainActor in replyHandler(await self.receive(messageData)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["preparation"] as? Data
        let rawLanguage = applicationContext["language"] as? String
        Task { @MainActor in
            if let rawLanguage { self.receiveLanguage(rawLanguage) }
            if let data { await self.receivePreparation(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WatchConnectivity removes the temporary URL after this callback.
        // Read the bounded payload before crossing to the coordinator's actor.
        guard let identifier = file.metadata?["outboxID"] as? String,
              let size = try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16 * 1024 * 1024,
              let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in await self.receiveFile(data, identifier: identifier) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let identifier = userInfo["logoutReceipt"] as? String,
              let runID = userInfo["runID"] as? String else { return }
        Task { @MainActor in self.receiveReceipt(identifier: identifier, runID: runID) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }
    #endif
}
