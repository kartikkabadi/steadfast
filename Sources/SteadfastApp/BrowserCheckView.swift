import AppKit
import SwiftUI

struct BrowserCheckView: View {
    static let domain = Model.browserCheckDomain
    // Opening a different host for the baseline avoids reusing its connection.
    private static let baselineHost = "www.example.com"

    @Bindable var model: Model
    @State private var openedBaseline = false
    @State private var endsAt: Date?
    @State private var testEnded = false
    @State private var outcome: BrowserCheckSheet.Stage?
    @State private var error: String?

    private var stage: BrowserCheckSheet.Stage {
        if let outcome { return outcome }
        if let endsAt { return testEnded || Date.now >= endsAt ? .expired : .running(endsAt) }
        return openedBaseline ? .ready : .intro
    }

    var body: some View {
        BrowserCheckSheet(stage: stage, busy: model.busy, canStart: model.serviceReady, error: error, act: act)
            .interactiveDismissDisabled(model.busy)
            .task(id: endsAt) {
                guard let endsAt else { return }
                do { try await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow))) }
                catch { return }
                testEnded = true
            }
            .onChange(of: error) { _, message in
                if let message {
                    NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                         userInfo: [.announcement: message])
                }
            }
    }

    private func act(_ action: BrowserCheckSheet.Action) {
        switch action {
        case .close: model.closeComposer()
        case .openBaseline: openedBaseline = openPage(Self.baselineHost)
        case .start:
            Task {
                error = nil
                do {
                    testEnded = false
                    endsAt = try await model.startBrowserCheck()
                    _ = openPage(Self.domain)
                } catch { self.error = error.localizedDescription }
            }
        case .reopen: _ = openPage(Self.domain)
        case .blocked: outcome = .blocked; error = nil
        case .loaded: outcome = .loaded; error = nil
        case .retry:
            outcome = nil
            error = nil
            if let endsAt, endsAt <= Date.now {
                self.endsAt = nil
                openedBaseline = false
            }
        }
    }

    @discardableResult private func openPage(_ host: String) -> Bool {
        var url = URLComponents()
        url.scheme = "https"
        url.host = host
        url.queryItems = [URLQueryItem(name: "steadfast", value: UUID().uuidString)]
        guard let url = url.url, NSWorkspace.shared.open(url) else {
            error = "couldn't open the browser. open \(host) in your browser and try again."
            return false
        }
        error = nil
        return true
    }
}

struct BrowserCheckSheet: View {
    enum Stage {
        case intro, ready, running(Date), blocked, loaded, expired

        var title: String {
            switch self {
            case .intro: "Test Browser Blocking"
            case .ready: "Ready to Start?"
            case .running: "Did the Page Load?"
            case .blocked: "Blocking Worked"
            case .loaded: "The Page Still Loaded"
            case .expired: "Test Ended"
            }
        }

        var detail: String {
            switch self {
            case .intro: "Open example.com in your default browser to check that it loads."
            case .ready: "If the page loaded, start a one-minute block. Steadfast will open a new tab."
            case .running: "Check the new example.com tab and choose what happened."
            case .blocked: "Your browser blocked example.com during the test."
            case .loaded: "Try a private window. If it still loads, check your browser’s secure DNS and VPN settings."
            case .expired: "Start over to run another one-minute browser check."
            }
        }
    }

    enum Action { case close, openBaseline, start, reopen, blocked, loaded, retry }

    let stage: Stage
    let busy: Bool
    let canStart: Bool
    let error: String?
    let act: (Action) -> Void

    /// The same plate as every other sheet: title and detail on the left, the
    /// close door top right, answers in the foot on the right.
    var body: some View {
        Plate(stage.title, subtitle: stage.detail, close: { act(.close) }) {
            VStack(alignment: .leading, spacing: 10) {
                if case let .running(end) = stage {
                    Line("Test block", "Ends at \(end.formatted(date: .omitted, time: .standard))") { EmptyView() }
                        .monospacedDigit()
                        .quietGroup()
                }
                if let error { ErrorNote(error) }
            }
        } foot: {
            HStack(spacing: 8) {
                if case .running = stage {
                    QuietLink(title: "Reopen Test Page", leading: true) { act(.reopen) }
                }
                Spacer()
                actions
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch stage {
        case .intro:
            pair("Cancel", "Open Example Page", action: .openBaseline)
        case .ready:
            pair("Cancel", busy ? "Starting…" : "Start Test Block", action: .start)
        case .running:
            SecondaryButton(title: "Page Loaded") { act(.loaded) }
            Button("Page Was Blocked") { act(.blocked) }.buttonStyle(PrimaryStyle())
        case .blocked:
            Button("Done") { act(.close) }.buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
        case .loaded:
            pair("Done", "Try Again", action: .retry)
        case .expired:
            pair("Done", "Start Over", action: .retry)
        }
    }

    @ViewBuilder private func pair(_ dismiss: String, _ title: String, action: Action) -> some View {
        SecondaryButton(title: dismiss) { act(.close) }.disabled(busy)
        Button(title) { act(action) }
            .buttonStyle(PrimaryStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(action == .start && (busy || !canStart))
    }
}
