import Foundation

struct URLRule: Decodable {
    let id: String
    let pattern: String
    let profile: String?
    let ask: Bool?
    let enabled: Bool?
}

struct RuleConfigurationError: LocalizedError {
    let message: String
    var errorDescription: String? { "Routing rules: \(message)" }
}

struct URLRules {
    static let file = RuleStore.directory.appendingPathComponent("routing-rules.json")
    let entries: [(rule: URLRule, regex: NSRegularExpression)]

    init(file: URL = URLRules.file) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { entries = []; return }
        let data = try Data(contentsOf: file)
        // Reject typos instead of silently ignoring conditions or actions.
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(document.keys).isSubset(of: ["version", "rules"]),
              let rules = document["rules"] as? [[String: Any]],
              rules.allSatisfy({ Set($0.keys).isSubset(of: ["id", "pattern", "profile", "ask", "enabled"]) }) else {
            throw RuleConfigurationError(message: "Expected version and rules; a field is missing or unknown.")
        }
        struct Document: Decodable { let version: Int; let rules: [URLRule] }
        let decoded = try JSONDecoder().decode(Document.self, from: data)
        guard decoded.version == 1 else { throw RuleConfigurationError(message: "Unsupported version. Expected 1.") }
        var seen = Set<String>()
        entries = try decoded.rules.map { rule in
            guard !rule.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(rule.id).inserted else {
                throw RuleConfigurationError(message: "Each rule needs a unique, nonempty id.")
            }
            guard !rule.pattern.isEmpty, (rule.profile != nil) != (rule.ask == true) else {
                throw RuleConfigurationError(message: "Rule '\(rule.id)' needs a pattern and either profile or ask: true.")
            }
            if let profile = rule.profile, !Profiles.validID(profile) {
                throw RuleConfigurationError(message: "Rule '\(rule.id)' has an invalid profile directory.")
            }
            let regex: NSRegularExpression
            do { regex = try NSRegularExpression(pattern: rule.pattern) }
            catch { throw RuleConfigurationError(message: "Rule '\(rule.id)' has an invalid regular expression.") }
            return (rule, regex)
        }
    }

    func match(_ link: WebLink) -> URLRule? {
        let range = NSRange(link.raw.startIndex..<link.raw.endIndex, in: link.raw)
        return entries.first {
            $0.rule.enabled != false && $0.regex.firstMatch(in: link.raw, range: range) != nil
        }?.rule
    }
}

struct RoutingDecision {
    let source: String
    let ruleID: String?
    let profile: ChromeProfile?
}

enum RoutingPolicy {
    static func decide(_ link: WebLink, profiles: [ChromeProfile], rules: URLRules, saved: RuleStore?) -> RoutingDecision {
        if let rule = rules.match(link) {
            // An ask rule or an unavailable profile must not fall through to a broader rule.
            return RoutingDecision(source: "custom", ruleID: rule.id, profile: profiles.first { $0.id == rule.profile })
        }
        if let profile = saved?.destination(for: link, profiles: profiles) {
            return RoutingDecision(source: "website", ruleID: nil, profile: profile)
        }
        return RoutingDecision(source: "unmatched", ruleID: nil, profile: nil)
    }
}

// These commands never launch Chrome or change settings.
func runRulesCLI(_ arguments: [String]) -> Int32? {
    guard let command = arguments.first, ["--profiles", "--validate-rules", "--explain", "--help"].contains(command) else { return nil }
    func output(_ value: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
    do {
        var remaining = Array(arguments.dropFirst())
        var file = URLRules.file
        if let index = remaining.firstIndex(of: "--rules-file") {
            guard index + 1 < remaining.count else { throw RuleConfigurationError(message: "--rules-file needs a path.") }
            file = URL(fileURLWithPath: remaining[index + 1])
            guard FileManager.default.fileExists(atPath: file.path) else { throw RuleConfigurationError(message: "The specified rules file does not exist.") }
            remaining.removeSubrange(index...index + 1)
        }
        if command == "--help" {
            print("""
            --profiles                         List Chrome profile directories and names.
            --validate-rules                   Validate the routing rules file.
            --explain URL                      Show which profile/rule would handle a URL, without opening it.
            --rules-file PATH                  Use an alternate file for validation or explanation.
            Default rules: \(URLRules.file.path)
            """)
            return 0
        }
        guard remaining.count == (command == "--explain" ? 1 : 0) else { throw RuleConfigurationError(message: "Unexpected arguments. Use --help.") }
        let profiles = try Profiles.read()
        if command == "--profiles" {
            output(profiles.map { ["id": $0.id, "name": $0.name] }); return 0
        }
        let rules = try URLRules(file: file)
        if command == "--validate-rules" {
            let unavailable = rules.entries.filter { entry in
                entry.rule.enabled != false && entry.rule.profile != nil && !profiles.contains { $0.id == entry.rule.profile }
            }.map { $0.rule.id }
            output(["ok": true, "rules": rules.entries.count, "file": file.path, "unavailableProfileRules": unavailable])
        } else {
            let link = try WebLink(remaining[0])
            let decision = RoutingPolicy.decide(link, profiles: profiles, rules: rules, saved: try RuleStore())
            output(["action": decision.profile == nil ? "ask" : "open", "source": decision.source,
                    "rule": decision.ruleID as Any? ?? NSNull(), "profile": decision.profile?.id as Any? ?? NSNull(),
                    "profileName": decision.profile?.name as Any? ?? NSNull()])
        }
        return 0
    } catch {
        output(["ok": false, "error": error.localizedDescription]); return 1
    }
}
