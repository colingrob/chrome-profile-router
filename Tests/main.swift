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
let customFile = temporary.appendingPathComponent("routing-rules.json")
func writeRules(_ rules: [[String: Any]], version: Int = 1) throws {
    try JSONSerialization.data(withJSONObject: ["version": version, "rules": rules]).write(to: customFile, options: .atomic)
}
let projectPattern = #"^https://example\.com/team/project(?:[/?#]|$)"#
let projectRule: [String: Any] = ["id": "project", "pattern": projectPattern, "profile": "Profile 10"]
try check(URLRules(file: customFile).entries.isEmpty, "absent custom file preserves existing routing")
try writeRules([projectRule])
let projectRules = try URLRules(file: customFile)
for raw in ["https://example.com/team/project", "https://example.com/team/project/pull/12?tab=files#diff", "https://example.com/team/project?q=1"] {
    try check(projectRules.match(WebLink(raw))?.id == "project", "standard regex covers root and descendants")
}
for raw in ["https://example.com/team/project-fork", "https://example.com.evil.test/team/project", "https://elsewhere.test/?next=https://example.com/team/project"] {
    try check(projectRules.match(WebLink(raw)) == nil, "anchored rule does not overmatch")
}
let saved = try RuleStore(file: temporary.appendingPathComponent("saved.json"))
try saved.set("example.com", profileID: "Default")
let projectLink = try WebLink("https://example.com/team/project/issues/1")
try check(RoutingPolicy.decide(projectLink, profiles: profiles, rules: projectRules, saved: saved).profile?.id == "Profile 10", "custom rules override broad saved website choice")
try check(RoutingPolicy.decide(WebLink("https://example.com/elsewhere"), profiles: profiles, rules: projectRules, saved: saved).source == "website", "nonmatches keep saved website fallback")
try check(RoutingPolicy.decide(WebLink("https://unknown.test"), profiles: profiles, rules: projectRules, saved: saved).source == "unmatched", "unknown URL asks")
try check(RoutingPolicy.decide(projectLink, profiles: [profiles[0]], rules: projectRules, saved: saved).profile == nil, "missing custom destination asks instead of falling through")
let askRule: [String: Any] = ["id": "ask", "pattern": "example", "ask": true]
try writeRules([askRule, projectRule])
let decision = RoutingPolicy.decide(projectLink, profiles: profiles, rules: try URLRules(file: customFile), saved: saved)
try check(decision.ruleID == "ask" && decision.profile == nil, "first match wins and ask suppresses broad fallback")
try writeRules([projectRule, askRule])
try check(URLRules(file: customFile).match(projectLink)?.id == "project", "edited order applies on next load")
try writeRules([["id": "off", "pattern": ".*", "ask": true, "enabled": false], projectRule])
try check(URLRules(file: customFile).match(projectLink)?.id == "project", "disabled rules skipped")
try writeRules([["id": "query", "pattern": #"[?&]workspace=work(?:&|#|$)"#, "profile": "Profile 10"]])
try check(URLRules(file: customFile).match(WebLink("https://any.test/path?a=1&workspace=work#home"))?.id == "query", "arbitrary query matching uses same regex API")
try writeRules([["id": "fragment", "pattern": "#work$", "ask": true]])
try check(URLRules(file: customFile).match(WebLink("https://any.test/path#work"))?.id == "fragment", "fragments can be matched")
try writeRules([["id": "case", "pattern": "(?i)^https://example\\.com/TEAM/", "ask": true]])
try check(URLRules(file: customFile).match(projectLink)?.id == "case", "standard inline regex options supported")
for invalid in [
    [["id": "bad", "pattern": "[", "ask": true]],
    [["id": "bad", "pattern": ".*"]],
    [["id": "bad", "pattern": ".*", "ask": true, "profile": "Default"]],
    [["id": "bad", "pattern": ".*", "profile": "../../bad"]],
    [["id": "bad", "pattern": ".*", "ask": true, "hostnmae": "example.com"]],
    [["id": "bad", "pattern": "", "ask": true]],
    [["id": "", "pattern": ".*", "ask": true]],
    [projectRule, projectRule]
] as [[[String: Any]]] {
    try writeRules(invalid)
    try rejects("invalid config rejected instead of silently routing") { _ = try URLRules(file: customFile) }
}
try writeRules([], version: 99)
try rejects("unsupported custom rules version rejected") { _ = try URLRules(file: customFile) }
try Data("broken".utf8).write(to: customFile)
try rejects("partial writes fail safely") { _ = try URLRules(file: customFile) }
try writeRules([projectRule])
try check(URLRules(file: customFile).match(projectLink)?.id == "project", "valid replacement recovers without app restart")
try saved.set("other.test", profileID: "Default")
try check(URLRules(file: customFile).match(projectLink)?.id == "project", "picker website writes do not overwrite agent rules")
print("\(checks) checks passed")
