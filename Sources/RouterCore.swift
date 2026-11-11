import Foundation

struct ChromeProfile: Codable, Identifiable, Equatable {
    let id: String
    let name: String
}

enum RouterError: LocalizedError {
    case invalidURL, invalidProfile, missingChrome, invalidMessage
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a complete http:// or https:// link."
        case .invalidProfile: return "That Chrome profile is no longer available. Choose another profile."
        case .missingChrome: return "Google Chrome could not be found in Applications."
        case .invalidMessage: return "The extension sent an unsupported request."
        }
    }
}

struct WebLink: Equatable {
    let raw: String
    let site: String
    init(_ raw: String) throws {
        guard raw.utf8.count <= 262144,
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.url != nil else { throw RouterError.invalidURL }
        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard !normalizedHost.isEmpty else { throw RouterError.invalidURL }
        let port = parts.port
        if let port, !(1...65535).contains(port) { throw RouterError.invalidURL }
        self.raw = raw
        self.site = normalizedHost + ((port == nil || (scheme == "https" && port == 443) || (scheme == "http" && port == 80)) ? "" : ":\(port!)")
    }
}

enum Profiles {
    static let chromeRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome")
    static func validID(_ id: String) -> Bool {
        id == "Default" || id.range(of: #"^Profile [0-9]+$"#, options: .regularExpression) != nil
    }
    static func read(root: URL = chromeRoot) throws -> [ChromeProfile] {
        let data = try Data(contentsOf: root.appendingPathComponent("Local State"))
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let profile = document?["profile"] as? [String: Any]
        let cache = profile?["info_cache"] as? [String: [String: Any]] ?? [:]
        return cache.compactMap { id, info -> ChromeProfile? in
            guard validID(id), info["is_omitted_from_profile_list"] as? Bool != true,
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path) else { return nil }
            return ChromeProfile(id: id, name: info["name"] as? String ?? id)
        }.sorted {
            if ($0.id == "Default") != ($1.id == "Default") { return $0.id == "Default" }
            let leftActive = cache[$0.id]?["active_time"] as? Double ?? 0
            let rightActive = cache[$1.id]?["active_time"] as? Double ?? 0
            if leftActive != rightActive { return leftActive > rightActive }
            return ($0.name, $0.id) < ($1.name, $1.id)
        }
    }
}

struct RoutingPreferences: Codable {
    var version = 1
    var routes: [String: String] = [:]
}

final class RuleStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Chrome Profile Router")
    let file: URL
    private(set) var preferences: RoutingPreferences
    init(file: URL = RuleStore.directory.appendingPathComponent("rules.json")) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            preferences = try JSONDecoder().decode(RoutingPreferences.self, from: Data(contentsOf: file))
        } else { preferences = RoutingPreferences() }
    }
    func destination(for link: WebLink, profiles: [ChromeProfile]) -> ChromeProfile? {
        guard let id = preferences.routes[link.site] else { return nil }
        return profiles.first { $0.id == id }
    }
    func set(_ site: String, profileID: String?) throws {
        if let profileID, !Profiles.validID(profileID) { throw RouterError.invalidProfile }
        var next = preferences
        next.routes[site] = profileID
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        preferences = next
    }
}

enum ChromeLauncher {
    static func arguments(link: WebLink, profile: ChromeProfile) throws -> [String] {
        guard Profiles.validID(profile.id) else { throw RouterError.invalidProfile }
        return ["--profile-directory=\(profile.id)", link.raw]
    }
}
