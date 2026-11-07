import Foundation
import SteadfastCore

@main struct SyncLive {
    static func main() async throws {
        let args = CommandLine.arguments
        precondition(args.count == 4 && args[1...2].allSatisfy { $0.hasPrefix("dev.local.steadfast.test.") })
        let folder = URL(fileURLWithPath: args[3], isDirectory: true)
        let names = ["steadfast-e2e-\(UUID())", "steadfast-e2e-\(UUID())"]
        let defaults = names.map { UserDefaults(suiteName: $0)! }
        defer {
            for (name, prefs) in zip(names, defaults) { prefs.removePersistentDomain(forName: name) }
        }
        let devices = defaults.map { prefs in
            prefs.set(folder, forKey: "routineSyncFolder")
            return RoutineSync(defaults: prefs)
        }
        setenv("STEADFAST_TEST_SERVICE", args[1], 1)
        let model = Model()
        func use(_ index: Int) async throws {
            setenv("STEADFAST_TEST_SERVICE", args[index + 1], 1)
            model.snapshot = try await Client.send(Request(action: "status"), service: model.service)
            model.connected = true
        }
        func sync(_ index: Int) async throws {
            try await use(index)
            await devices[index].sync(for: model)
            if let error = devices[index].status { throw Failure(error) }
        }

        try await use(0)
        var routine = Routine(name: "reading", domains: ["example.org"], minutes: 30)
        _ = try await Client.send(Request(action: "save-routine", routine: routine), service: model.service)
        try await sync(0)
        try await sync(1)
        guard model.routines.first?.id == routine.id && model.routines.first?.minutes == 30 else {
            throw Failure("the receiving service did not import the routine")
        }
        print("pass: new routine syncs between independent services")

        routine.minutes = 45
        _ = try await Client.send(Request(action: "save-routine", routine: routine), service: model.service)
        try await sync(1)
        try await sync(0)
        precondition(model.routines.first?.minutes == 45)
        print("pass: edits sync back to the originating device")

        let shared = folder.appending(path: "Steadfast Routines")
        let file = try FileManager.default.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil)[0]
        let hidden = file.deletingPathExtension().appendingPathExtension("pending")
        try FileManager.default.moveItem(at: file, to: hidden)
        try await sync(0)
        precondition(model.routines.first?.minutes == 45)
        try FileManager.default.moveItem(at: hidden, to: file)
        print("pass: a temporarily missing device file preserves the routine")

        _ = try await Client.send(Request(action: "delete-routine", routineID: routine.id), service: model.service)
        try await sync(0)
        try await sync(1)
        precondition(model.routines.isEmpty)
        print("pass: deletions sync and do not resurrect an older revision")
    }
}
