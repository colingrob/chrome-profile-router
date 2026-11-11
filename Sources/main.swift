import AppKit
import SwiftUI

let bundleID = "local.colin.chrome-profile-router"

func readExactly(_ count: Int) -> Data? {
    var result = Data()
    while result.count < count {
        let chunk = FileHandle.standardInput.readData(ofLength: count - result.count)
        if chunk.isEmpty { return nil }
        result.append(chunk)
    }
    return result
}

func nativeHost() {
    func reply(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        var size = UInt32(data.count).littleEndian
        FileHandle.standardOutput.write(Data(bytes: &size, count: 4))
        FileHandle.standardOutput.write(data)
    }
    guard let header = readExactly(4) else { return }
    let length = header.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
    guard length > 0, length <= 524288, let data = readExactly(Int(length)) else {
        reply(["ok": false, "error": "Invalid message size."]); return
    }
    do {
        guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = message["action"] as? String else { throw RouterError.invalidMessage }
        if action == "ping" { reply(["ok": true, "version": "1.0.0"]); return }
        var destination = URLComponents()
        destination.scheme = "chromeroute"
        if action == "choose", let raw = message["url"] as? String {
            _ = try WebLink(raw)
            destination.host = "choose"
            destination.queryItems = [URLQueryItem(name: "url", value: raw)]
        } else if action == "settings" { destination.host = "settings" }
        else { throw RouterError.invalidMessage }
        guard let url = destination.url else { throw RouterError.invalidURL }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleID, url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        reply(process.terminationStatus == 0 ? ["ok": true] : ["ok": false, "error": "Open Chrome Profile Router once from Applications, then try again."])
    } catch { reply(["ok": false, "error": error.localizedDescription]) }
}

if CommandLine.arguments.contains("--native") {
    nativeHost()
    exit(0)
}

struct RouteRequest {
    let link: WebLink
    let forcePicker: Bool
}

final class RouterModel: ObservableObject {
    let demo = Bundle.main.object(forInfoDictionaryKey: "ProfileRouterDemo") as? Bool == true
    @Published var profiles: [ChromeProfile] = []
    @Published var routes: [String: String] = [:]
    @Published var current: RouteRequest?
    @Published var search = ""
    @Published var remember = true
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var isDefault = false
    @Published var input = ""
    @Published var queuedCount = 0
    var queue: [RouteRequest] = []
    var store: RuleStore?
    var showWindow: (() -> Void)?
    var hideWindow: (() -> Void)?

    init() {
        if demo {
            profiles = [ChromeProfile(id: "Default", name: "Personal"), ChromeProfile(id: "Profile 1", name: "Work"), ChromeProfile(id: "Profile 2", name: "Side project")]
            routes = ["github.com": "Profile 1", "calendar.google.com": "Default"]
            current = RouteRequest(link: try! WebLink("https://github.com/example/project"), forcePicker: true)
            isDefault = true
            return
        }
        do { store = try RuleStore(); routes = store!.preferences.routes }
        catch { self.error = "Saved choices could not be read. They have not been overwritten. \(error.localizedDescription)" }
        refreshProfiles()
        refreshDefault()
    }
    func refreshProfiles() {
        if demo { return }
        do { profiles = try Profiles.read() }
        catch { self.error = "Could not read Chrome’s profile list. \(error.localizedDescription)" }
    }
    func refreshDefault() {
        if demo { return }
        isDefault = ["http", "https"].allSatisfy {
            guard let url = URL(string: "\($0)://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
            return Bundle(url: app)?.bundleIdentifier == bundleID
        }
    }
    func makeDefault() {
        notice = "Select Chrome Profile Router under Default web browser."
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }
    func receive(_ url: URL) {
        do {
            if url.scheme?.lowercased() == "chromeroute" {
                if url.host == "settings" { showWindow?(); return }
                guard url.host == "choose", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let raw = parts.queryItems?.first(where: { $0.name == "url" })?.value else { throw RouterError.invalidURL }
                enqueue(try WebLink(raw), force: true)
            } else { enqueue(try WebLink(url.absoluteString), force: NSEvent.modifierFlags.contains(.option)) }
        } catch { self.error = error.localizedDescription; showWindow?() }
    }
    func enqueue(_ link: WebLink, force: Bool) {
        queue.append(RouteRequest(link: link, forcePicker: force))
        queuedCount = queue.count
        advance()
    }
    func advance() {
        guard current == nil, !busy, !queue.isEmpty else { return }
        refreshProfiles()
        let request = queue.removeFirst()
        queuedCount = queue.count
        current = request
        search = ""; remember = true; notice = nil
        if !request.forcePicker, let profile = store?.destination(for: request.link, profiles: profiles) {
            launch(profile, save: false)
        } else { showWindow?() }
    }
    func openInput() {
        do { let link = try WebLink(input.trimmingCharacters(in: .whitespacesAndNewlines)); input = ""; enqueue(link, force: true) }
        catch { self.error = error.localizedDescription }
    }
    func launch(_ profile: ChromeProfile, save: Bool) {
        if demo { current = nil; return }
        guard let request = current, !busy else { return }
        do {
            let fresh = try Profiles.read()
            guard fresh.contains(where: { $0.id == profile.id }) else { throw RouterError.invalidProfile }
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { throw RouterError.missingChrome }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", "-a", app.path, "--args"] + (try ChromeLauncher.arguments(link: request.link, profile: profile))
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            busy = true
            process.terminationHandler = { process in
                DispatchQueue.main.async {
                    self.busy = false
                    guard process.terminationStatus == 0 else {
                        self.error = "Chrome could not open this link. Try choosing the profile again."
                        self.showWindow?(); return
                    }
                    if save {
                        do {
                            guard let store = self.store else { throw CocoaError(.fileReadCorruptFile) }
                            try store.set(request.link.site, profileID: profile.id)
                            self.routes = store.preferences.routes
                        } catch {
                            self.error = "The link opened, but the choice could not be saved. \(error.localizedDescription)"
                        }
                    }
                    self.current = nil
                    if self.error == nil { self.hideWindow?() } else { self.showWindow?() }
                    self.advance()
                }
            }
            try process.run()
        } catch { busy = false; self.error = error.localizedDescription; showWindow?() }
    }
    func cancel() {
        guard !busy else { return }
        current = nil; hideWindow?(); advance()
    }
    func forget(_ site: String) {
        do { try store?.set(site, profileID: nil); routes = store?.preferences.routes ?? [:] }
        catch { self.error = error.localizedDescription }
    }
}

struct RouterView: View {
    @ObservedObject var model: RouterModel
    var filteredProfiles: [ChromeProfile] {
        model.profiles.filter { model.search.isEmpty || $0.name.localizedCaseInsensitiveContains(model.search) || $0.id.localizedCaseInsensitiveContains(model.search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 18, weight: .medium)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.current == nil ? "Profile Router" : "Open with…").font(.system(size: 17, weight: .semibold))
                    if let request = model.current { Text(request.link.site).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            if let message = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }.padding(12).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if model.current != nil {
                TextField("Find a profile", text: $model.search).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Find a profile")
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredProfiles) { profile in
                            Button { model.launch(profile, save: model.remember) } label: {
                                HStack(spacing: 10) {
                                    Text(String(profile.name.prefix(1)).uppercased()).font(.system(size: 12, weight: .medium))
                                        .frame(width: 28, height: 28).background(Color.indigo.opacity(0.09), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(profile.name).font(.system(size: 13, weight: .medium))
                                    }
                                    Spacer()
                                    Text(profile.id == "Default" ? "Personal" : profile.id).font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                .accessibilityLabel("Open in \(profile.name), \(profile.id)")
                                .disabled(model.busy)
                        }
                        if filteredProfiles.isEmpty {
                            Text(model.profiles.isEmpty ? "No Chrome profiles found. Open Chrome and create a profile first." : "No matching profiles.")
                                .foregroundStyle(.secondary).padding()
                        }
                    }
                }.frame(maxHeight: .infinity)
                Divider()
                Toggle("Remember for this site", isOn: $model.remember).toggleStyle(.checkbox).font(.system(size: 12)).disabled(model.busy)
                HStack {
                    Text(model.queuedCount > 0 ? "\(model.queuedCount) more links waiting" : "All profiles · One shared preference")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                }
            } else {
                HStack {
                    Image(systemName: model.isDefault ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(model.isDefault ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.isDefault ? "Routing external links" : "Make this your default browser").font(.system(size: 12))
                    }
                    Spacer()
                    if !model.isDefault { Button("Set up") { model.makeDefault() }.controlSize(.small) }
                }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                HStack {
                    TextField("Paste a link…", text: $model.input).textFieldStyle(.roundedBorder).onSubmit { model.openInput() }
                    Button("Choose…") { model.openInput() }.disabled(model.input.isEmpty)
                }
                HStack {
                    Text("Saved choices").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(model.profiles.count) profiles").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        if model.routes.isEmpty {
                            VStack(spacing: 10) {
                                Text("No saved choices yet").font(.system(size: 13, weight: .medium))
                                Text("Choose once. Next time, it opens there.").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(model.routes.keys.sorted(), id: \.self) { site in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(site).font(.system(size: 12, weight: .medium))
                                    Text(model.profiles.first { $0.id == model.routes[site] }?.name ?? "Profile unavailable — you’ll be asked again").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Forget") { model.forget(site) }.accessibilityLabel("Forget \(site)")
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                Text("Hold ⌥ when opening a link to choose again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(width: 380, height: 440)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = RouterModel()
    var window: NSWindow!
    var status: NSStatusItem!
    var receivedURL = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Chrome Profile Router", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Chrome Profile Router"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RouterView(model: model))
        window.center()
        model.showWindow = { [weak self] in self?.show() }
        model.hideWindow = { [weak self] in self?.window.orderOut(nil) }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Chrome Profile Router")
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "Profiles & saved choices…", action: #selector(showSettings), keyEquivalent: "")
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusMenu.items.forEach { $0.target = self }
        statusMenu.items.last?.target = NSApp
        status.menu = statusMenu
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !self.receivedURL { self.show() }
        }
    }
    func show() {
        model.refreshDefault(); model.refreshProfiles()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showSettings() { show() }
    func application(_ application: NSApplication, open urls: [URL]) { receivedURL = true; urls.forEach { model.receive($0) } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.busy { return false }
        if model.current != nil { model.cancel() }
        else { sender.orderOut(nil) }
        return false
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshDefault() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
