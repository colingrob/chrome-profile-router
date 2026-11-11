import Foundation

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
    guard try condition() else { fatalError("FAIL: \(label)") }
    checks += 1
    print("PASS: \(label)")
}
func rejects(_ label: String, _ action: () throws -> Void) throws {
    do { try action() } catch { checks += 1; print("PASS: \(label)"); return }
    fatalError("FAIL: \(label)")
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

try check(WebLink("https://EXAMPLE.com/path?q=a%26b#part").site == "example.com", "host normalization")
try check(WebLink("https://example.com.:443/a").site == "example.com", "trailing dot and default TLS port")
try check(WebLink("http://example.com:80/").site == "example.com", "default HTTP port")
try check(WebLink("http://localhost:8765/").site == "localhost:8765", "nonstandard ports stay separate")
try check(WebLink("http://[::1]:8765/").site == "[::1]:8765", "IPv6 loopback")
for raw in ["javascript:alert(1)", "file:///etc/passwd", "chrome://settings", "data:text/html,hello", "--profile-directory=Default", "https:///", "hello", "https://example.com\n--flag", "http://example.com:0/", "http://example.com:99999/"] {
    try rejects("reject unsupported or malformed URL") { _ = try WebLink(raw) }
}
let raw = "https://example.com/a%2Fb?code=a%2Bb%3D&state=x%26y&next=https%3A%2F%2Fexample.net%2F#fragment"
let link = try WebLink(raw)
try check(link.raw == raw, "OAuth-like query, escaping, and fragment preserved byte for byte")
let profiles = [ChromeProfile(id: "Default", name: "Colin"), ChromeProfile(id: "Profile 10", name: "revyl.ai")]
let file = temporary.appendingPathComponent("prefs/rules.json")
let store = try RuleStore(file: file)
try check(store.destination(for: link, profiles: profiles) == nil, "first visit asks")
try store.set(link.site, profileID: "Profile 10")
try check(store.destination(for: link, profiles: profiles)?.name == "revyl.ai", "saved choice resolves")
try check(RuleStore(file: file).destination(for: link, profiles: profiles)?.id == "Profile 10", "choice survives restart")
try check(store.destination(for: WebLink("https://sub.example.com"), profiles: profiles) == nil, "subdomains do not inherit accidentally")
try check(store.destination(for: WebLink("https://example.com.evil.test"), profiles: profiles) == nil, "suffix lookalike does not match")
try check(store.destination(for: link, profiles: [profiles[0]]) == nil, "deleted profile prompts again")
try store.set(link.site, profileID: "Default")
try check(store.destination(for: link, profiles: profiles)?.id == "Default", "choice can be changed")
try store.set(link.site, profileID: nil)
try check(RuleStore(file: file).preferences.routes.isEmpty, "forget persists")
try rejects("profile path traversal rejected") { try store.set(link.site, profileID: "../../other") }
try check(ChromeLauncher.arguments(link: link, profile: profiles[1]) == ["--profile-directory=Profile 10", raw], "launch arguments preserve URL and profile as separate values")
try rejects("profile flag injection rejected") { _ = try ChromeLauncher.arguments(link: link, profile: ChromeProfile(id: "--incognito", name: "Bad")) }
let text = try String(contentsOf: file, encoding: .utf8)
try check(!text.contains("code=") && !text.contains("fragment"), "saved file contains no URL tokens or history")
try "invalid json".write(to: file, atomically: true, encoding: .utf8)
try rejects("corrupt store is not silently replaced") { _ = try RuleStore(file: file) }
try check(String(contentsOf: file, encoding: .utf8) == "invalid json", "corrupt file preserved")

let chromeRoot = temporary.appendingPathComponent("Chrome")
for id in ["Default", "Profile 10", "Profile 2", "Guest Profile"] {
    try FileManager.default.createDirectory(at: chromeRoot.appendingPathComponent(id), withIntermediateDirectories: true)
}
let metadata: [String: Any] = ["profile": ["info_cache": [
    "Default": ["name": "Colin"], "Profile 10": ["name": "revyl.ai"],
    "Profile 2": ["name": "Hidden", "is_omitted_from_profile_list": true],
    "Profile 99": ["name": "Deleted"], "Guest Profile": ["name": "Guest"]
]]]
try JSONSerialization.data(withJSONObject: metadata).write(to: chromeRoot.appendingPathComponent("Local State"))
try check(Profiles.read(root: chromeRoot) == profiles, "only valid existing visible profiles discovered")
print("\(checks) checks passed")
