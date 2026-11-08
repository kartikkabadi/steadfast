import SwiftUI
import AppKit
import SteadfastCore

if CommandLine.arguments.contains("--preview") || Bundle.main.bundleIdentifier?.hasPrefix("dev.local.steadfast.preview.") == true {
    guard let service = ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"],
          service.hasPrefix("dev.local.steadfast.test.") else {
        fputs("preview requires its disposable service; run scripts/preview.sh\n", stderr)
        exit(1)
    }
}

struct SteadfastApp: App {
    @State private var model = Model()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismissWindow) private var dismissWindow
    static var suppressWindow = CommandLine.arguments.contains("--background")
    private var commandsUnavailable: Bool { model.busy || model.panel != nil }
    var body: some Scene {
        Window("steadfast", id: "main") {
            RootView(model: model)
                .frame(minWidth: 640, minHeight: 600)
                .onAppear {
                    // A background launch only explains a blocked app; window restoration must not open the window.
                    if SteadfastApp.suppressWindow {
                        SteadfastApp.suppressWindow = false
                        dismissWindow(id: "main")
                        return
                    }
                    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
                }
                .containerBackground(.clear, for: .window)
                .task(id: scenePhase) {
                    if scenePhase == .active { await model.checkForUpdate() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 680)
        // The service opens Steadfast in the background to explain a blocked app; no window then.
        .defaultLaunchBehavior(CommandLine.arguments.contains("--background") ? .suppressed : .automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Block") { model.startDraft() }.keyboardShortcut("n").disabled(commandsUnavailable)
                Button("New Routine") { model.newRoutine() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(commandsUnavailable)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.error = nil; model.panel = .settings }.keyboardShortcut(",").disabled(commandsUnavailable)
            }
            CommandMenu("Go") {
                Button("Today") { model.page = .block; model.error = nil }.keyboardShortcut("1").disabled(commandsUnavailable)
                Button("Routines") { model.page = .routines; model.error = nil }.keyboardShortcut("2").disabled(commandsUnavailable)
                Button("Progress") { model.page = .history; model.error = nil }.keyboardShortcut("3").disabled(commandsUnavailable)
            }
            CommandGroup(after: .textEditing) {
                Button("Find Websites") { model.searchRequested += 1 }.keyboardShortcut("f")
                    .disabled(commandsUnavailable)
            }
        }

        MenuBarExtra {
            StatusMenu(model: model).focusEffectDisabled()
        } label: {
            Image(nsImage: StatusMenu.icon).accessibilityLabel("Steadfast")
                .onAppear { model.outcomes.start() }
                .task {
                    do {
                        let updates = try ServiceEvents.updates(for: model.service)
                        await model.refresh()
                        for await _ in updates { await model.refresh() }
                    } catch {
                        // Keep status current if the system notification channel is unavailable.
                        while !Task.isCancelled {
                            await model.refresh()
                            do { try await Task.sleep(for: .seconds(30)) } catch { break }
                        }
                    }
                }
                .task(id: !model.serviceReady) {
                    guard !model.serviceReady else { return }
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(10)) } catch { break }
                        await model.refresh()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ServiceEvents.disconnected).receive(on: RunLoop.main)) { event in
                    guard event.object as? String == model.service else { return }
                    model.serviceDisconnected()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

if CommandLine.arguments.contains("--can-uninstall") {
    Task {
        do {
            let snapshot = try await Client.send(Request(action: "prepare-uninstall"))
            guard snapshot.policy.active(at: snapshot.now).isEmpty, snapshot.enforcementError == nil else { throw Failure("active commitments remain or enforcement could not be cleaned up") }
            print("all commitments expired; managed dns configuration has been restored"); exit(0)
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    RunLoop.main.run()
} else if let index = CommandLine.arguments.firstIndex(of: "--request-json"), CommandLine.arguments.count > index + 1 {
    let raw = CommandLine.arguments[index + 1]
    Task {
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(raw.utf8))
            let service = ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"] ?? ServiceName.production
            let testPrefix = "dev.local.steadfast.test."
            let testService = service.hasPrefix(testPrefix) && service.count > testPrefix.count
            guard service == ServiceName.production || testService else { throw Failure("invalid test service") }
            guard testService || request.action == "status" else { throw Failure("production requests must be made through the app") }
            let snapshot = try await Client.send(request, service: service)
            if testService {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(snapshot))
            } else {
                var status: [String: Any] = ["sandbox": snapshot.sandbox]
                if snapshot.enforcementError != nil { status["enforcementError"] = "protection needs attention" }
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]))
            }
            print("")
            exit(0)
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    RunLoop.main.run()
} else {
    AppNotices.shared.start(service: ProcessInfo.processInfo.environment["STEADFAST_TEST_SERVICE"] ?? ServiceName.production)
    // Opened by the service only to explain a blocked app: stay in the menu bar until a window opens.
    if CommandLine.arguments.contains("--background") {
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
    SteadfastApp.main()
}
