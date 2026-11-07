import AppKit
import CryptoKit
import Foundation
import SteadfastCore

nonisolated private struct SyncEntry: Codable, Sendable {
    let id: UUID
    let revision: UInt64
    let template: RoutineTemplate?
}

nonisolated private struct SyncFile: Codable, Sendable {
    let schema: Int
    let device: UUID
    var entries: [SyncEntry]
}

nonisolated private struct SyncState: Codable, Sendable {
    var device = UUID()
    var baseline: [RoutineTemplate] = []
    var known: [SyncFile] = []

    mutating func exchange(in folder: URL, local: [RoutineTemplate]) throws -> [RoutineTemplate] {
        let manager = FileManager.default
        var directory: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
            throw Failure("the shared folder is unavailable")
        }
        let library = folder.appending(path: "Steadfast Routines", directoryHint: .isDirectory)
        if !manager.fileExists(atPath: library.path) {
            do { try manager.createDirectory(at: library, withIntermediateDirectories: false) }
            catch let error as CocoaError where error.code == .fileWriteFileExists {}
        }
        let libraryValues = try library.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard libraryValues.isDirectory == true, libraryValues.isSymbolicLink == false else {
            throw Failure("choose a shared folder without a linked routine library")
        }
        let resources: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        let files = try manager.contentsOfDirectory(at: library, includingPropertiesForKeys: Array(resources))
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        guard files.count <= 32 else { throw Failure("the shared folder has too many device files") }

        var documents = Dictionary(uniqueKeysWithValues: known.map { ($0.device, $0) })
        for file in files {
            let values = try file.resourceValues(forKeys: resources)
            guard values.isRegularFile == true, values.isSymbolicLink == false, (values.fileSize ?? Int.max) <= 1_048_576 else {
                throw Failure("a shared device file is invalid")
            }
            let data = try Data(contentsOf: file)
            let document = try JSONDecoder().decode(SyncFile.self, from: data)
            guard document.schema == 1, document.device.uuidString == file.deletingPathExtension().lastPathComponent,
                  Set(document.entries.map(\.id)).count == document.entries.count,
                  document.entries.allSatisfy({ $0.template == nil || $0.template?.id == $0.id }) else {
                throw Failure("a shared device file is invalid")
            }
            var entries = Dictionary(uniqueKeysWithValues: (documents[document.device]?.entries ?? []).map { ($0.id, $0) })
            for entry in document.entries where entry.revision >= (entries[entry.id]?.revision ?? 0) {
                entries[entry.id] = entry
            }
            documents[document.device] = SyncFile(schema: 1, device: document.device, entries: Array(entries.values))
        }
        guard documents.count <= 32 else { throw Failure("the shared folder has too many devices") }

        var own = documents[device] ?? SyncFile(schema: 1, device: device, entries: [])
        let prior = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let changed = Set(prior.keys).union(current.keys).filter { prior[$0] != current[$0] }
        if !changed.isEmpty {
            guard documents[device] != nil || documents.count < 32 else {
                throw Failure("the shared folder has too many devices")
            }
            let clock = documents.values.flatMap(\.entries).map(\.revision).max() ?? 0
            guard clock < UInt64.max else { throw Failure("a shared device file has an invalid revision") }
            own.entries.removeAll { changed.contains($0.id) }
            own.entries.append(contentsOf: changed.map { SyncEntry(id: $0, revision: clock + 1, template: current[$0]) })
            let file = library.appending(path: device.uuidString + ".json")
            let encoded = try JSONEncoder().encode(own)
            guard encoded.count <= 1_048_576 else { throw Failure("the shared device file is full") }
            try encoded.write(to: file, options: .atomic)
            documents[device] = own
        }

        known = Array(documents.values)
        var winners: [UUID: SyncEntry] = [:]
        for document in documents.values.sorted(by: { $0.device.uuidString < $1.device.uuidString }) {
            for entry in document.entries where entry.revision >= (winners[entry.id]?.revision ?? 0) {
                winners[entry.id] = entry
            }
        }
        return winners.values.compactMap(\.template).sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

@Observable final class RoutineSync {
    private static let folderKey = "routineSyncFolder"
    private let defaults: UserDefaults
    private(set) var folder: URL?
    private(set) var busy = false
    private(set) var status: String?
    private var task: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folder = defaults.url(forKey: Self.folderKey)
    }

    func chooseFolder(for model: Model) async {
        let panel = NSOpenPanel()
        panel.title = "Choose a Shared Folder"
        panel.prompt = "Sync Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard await panel.begin() == .OK, let url = panel.url else { return }
        folder = url
        defaults.set(url, forKey: Self.folderKey)
        start(for: model)
        await sync(for: model)
    }

    func stop() {
        task?.cancel()
        task = nil
        folder = nil
        status = nil
        defaults.removeObject(forKey: Self.folderKey)
    }

    func start(for model: Model) {
        guard folder != nil, task == nil else { return }
        task = Task { [weak self, weak model] in
            while !Task.isCancelled {
                if let self, let model { await self.sync(for: model) }
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    func sync(for model: Model) async {
        guard let folder, !busy, !model.busy, model.serviceReady else { return }
        busy = true
        defer { busy = false }
        let hash = SHA256.hash(data: Data(folder.standardizedFileURL.path.utf8))
        let key = "routineSync.\(hash.compactMap { String(format: "%02x", $0) }.joined())"
        do {
            var state: SyncState
            if let stored = defaults.data(forKey: key) {
                state = try JSONDecoder().decode(SyncState.self, from: stored)
            } else {
                state = SyncState()
                defaults.set(try JSONEncoder().encode(state), forKey: key)
            }
            let snapshot = try await Client.send(Request(action: "status"), service: model.service)
            guard self.folder == folder, !Task.isCancelled, snapshot.enforcementError == nil else { return }
            let local = snapshot.policy.routineTemplates
            let exchangeState = state
            let exchange = try await Task.detached(priority: .utility) {
                var updated = exchangeState
                let desired = try updated.exchange(in: folder, local: local)
                return (updated, desired)
            }.value
            guard self.folder == folder, !Task.isCancelled else { return }
            let desired = exchange.1
            state = exchange.0
            state.baseline = local
            defaults.set(try JSONEncoder().encode(state), forKey: key)
            if desired != local {
                let change = RoutineSyncChange(expected: local, desired: desired)
                let result = try await Client.send(Request(action: "sync-routines", routineSync: change), service: model.service)
                state.baseline = result.policy.routineTemplates
                if result.now >= (model.snapshot?.now ?? .distantPast) { model.snapshot = result }
                defaults.set(try JSONEncoder().encode(state), forKey: key)
            }
            if self.folder == folder { status = nil }
        } catch {
            if self.folder == folder && !Task.isCancelled { status = error.localizedDescription }
        }
    }
}
