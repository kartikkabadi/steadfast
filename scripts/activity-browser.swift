import AppKit

// A disposable native window exposing the same URL attribute as a browser.
@MainActor final class BrowserPage: NSView {
    var host = "example.com"
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { NSAccessibility.Role(rawValue: "AXWebArea") }
    override func accessibilityURL() -> URL? { URL(string: "https://\(host)/private/path?not-stored=1") }
    override func accessibilityLabel() -> String? { "A disposable page for the live activity check" }
}

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    let page = BrowserPage()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Steadfast activity check"
        let stack = NSStackView()
        stack.orientation = .vertical; stack.spacing = 24
        let label = NSTextField(labelWithString: "Disposable browser pages · no network requests")
        stack.addArrangedSubview(label)
        let buttons = NSStackView()
        for domain in ["example.com", "example.org"] {
            buttons.addArrangedSubview(NSButton(title: domain, target: self, action: #selector(change(_:))))
        }
        stack.addArrangedSubview(buttons)
        page.heightAnchor.constraint(equalToConstant: 100).isActive = true
        page.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(page)
        window.contentView = stack
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    @objc func change(_ sender: NSButton) {
        page.host = sender.title
        NSAccessibility.post(element: page, notification: .valueChanged)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
