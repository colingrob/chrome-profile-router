import AppKit

// A disposable source app for exercising real macOS external URL delivery.
final class Source: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let cases = [
        ("1. Personal first visit", "http://127.0.0.1:18764/personal-first"),
        ("2. Work first visit", "http://localhost:18764/work-first"),
        ("3. Personal remembered", "http://127.0.0.1:18764/personal-remembered"),
        ("4. Work remembered", "http://localhost:18764/work-remembered"),
        ("5. Encoded URL", "http://127.0.0.1:18764/a%2Fb?code=a%2Bb%3D&state=x%26y#fragment"),
        ("6. Queue two links", ""),
        ("7. HTTPS external link", "https://example.com/?router-test=https")
    ]
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 300, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Router Test Links"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 10
        for (index, test) in cases.enumerated() {
            let button = NSButton(title: test.0, target: self, action: #selector(openLink(_:)))
            button.tag = index; stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor), stack.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor)])
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openLink(_ button: NSButton) {
        if button.tag == 5 {
            for site in ["127.0.0.1", "localhost"] {
                var parts = URLComponents(); parts.scheme = "chromeroute"; parts.host = "choose"
                parts.queryItems = [URLQueryItem(name: "url", value: "http://\(site):18764/queued")]
                NSWorkspace.shared.open(parts.url!)
            }
        } else { NSWorkspace.shared.open(URL(string: cases[button.tag].1)!) }
    }
}
let app = NSApplication.shared
let delegate = Source(); app.delegate = delegate
app.setActivationPolicy(.regular); app.run()
