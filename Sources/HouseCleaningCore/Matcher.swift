import Foundation

public enum Verdict: Sendable, Equatable {
    case keep(String)
    case leftover(Confidence, String)
}

/// Decides whether an entry in ~/Library belongs to something that is still in use.
public struct Matcher: Sendable {
    /// Bundle-ID prefixes that belong to macOS itself or its developer tools.
    static let systemPrefixes = ["com.apple", "systemgroup.com.apple", "is.workflow", "org.cups", "org.swift"]

    /// Path fragments that mark iCloud data, which is never touched.
    static let iCloudMarkers = ["icloud", "clouddocs", "mobile documents", "ubiquity"]

    /// Name fragments of GitHub data, kept while VS Code or the gh CLI is installed.
    static let gitHubMarkers = ["github", "copilot"]

    /// Third-party SDKs that many apps share; their data is never attributable to one app.
    static let sharedVendors: Set<String> = [
        "io.sentry", "com.bugsnag", "org.sparkle-project", "com.crashlytics", "com.squirrel",
    ]

    /// Vendor prefixes too generic to say anything about who owns an entry.
    static let genericVendors: Set<String> = [
        "com.github", "io.github", "com.electron", "com.todesktop", "org.chromium",
    ]

    /// Normalized plain names of folders and files macOS itself creates.
    static let systemNames: Set<String> = [
        // Application Support
        "addressbook", "animoji", "appstore", "apple", "askpermission", "callhistorydb",
        "callhistorytransactions", "clouddocs", "controlcenter", "crashreporter", "defaultstore",
        "defaultstoreshm", "defaultstorewal", "differentialprivacy", "diskimages", "dock", "facetime",
        "familysettings", "fileprovider", "icloud", "ilifemediabrowser", "intelligenceflow", "knowledge",
        "mobilesync", "music", "networkserviceproxy", "spotlight", "summaryevents", "syncservices", "tv",
        "photos", "mail", "messages", "safari", "maps", "notes", "reminders", "calendars", "homekit",
        "siri", "shortcuts", "screentime", "accounts", "quicklook", "preview",
        // Caches
        "arfilecache", "cloudkit", "gamekit", "geoservices", "jetpackresourcebundles", "lsmimagecache",
        "passkit", "sharedimagecache", "trickplay", "tvappbag", "featuresconfig", "menkaureenabled",
        "familycircle", "metadata",
        // Logs
        "assistant", "baseband", "diagnosticreports", "photossearchaapbz", "privacypreservingmeasurement",
        "sirittsservice",
        // WebKit
        "databases", "webpush",
        // Preferences
        "byhost", "loginwindow", "pbs", "contextstoreagent", "diagnosticsagent", "internetaccountsmigrator",
        "knowledgeagent", "minilauncher", "safarilaunchagent", "skgactivityjournal", "tokenbucketratelimiter",
        "nobackup",
        // Group Containers
        "tvappservicescontainer",
    ]

    /// Words that appear in many app names and identify nothing on their own.
    static let stopWords: Set<String> = [
        "app", "apps", "the", "for", "and", "mac", "macos", "osx", "helper", "helpers", "framework",
        "project", "extension", "launcher", "agent", "service", "services", "desktop", "client", "studio",
        "pro", "plugin", "plugins", "update", "updater", "login", "item", "lite", "free", "beta", "plus",
        "tools", "support", "data", "cache", "caches", "software", "inc", "ltd", "gpu", "renderer", "xpc",
        "widget", "widgets", "shared", "core", "kit", "com", "org", "net", "group", "manager", "player",
        "edition", "community", "preview", "stable", "snapshot", "nightly", "dev", "logs", "settings",
    ]

    private let bundleIDs: [String: String]
    private let vendors: [String: String]
    private let names: [String: String]
    private let words: [String: String]
    private let zapPatterns: [String: String]
    private let gitHubToolOwner: String?

    public init(inventory: AppInventory) {
        bundleIDs = inventory.bundleIDOwners
        zapPatterns = inventory.zapPatterns
        gitHubToolOwner = inventory.gitHubToolOwner

        var vendors: [String: String] = [:]
        var words: [String: String] = [:]
        for (id, owner) in inventory.bundleIDOwners {
            if let vendor = Self.vendor(of: id), !Self.genericVendors.contains(vendor), vendors[vendor] == nil {
                vendors[vendor] = owner
            }
            for component in id.split(separator: ".").dropFirst() {
                for word in Self.words(in: String(component)) where words[word] == nil {
                    words[word] = owner
                }
            }
        }

        var names: [String: String] = [:]
        for (name, owner) in inventory.nameOwners {
            let normalized = Self.normalize(name)
            if !normalized.isEmpty, names[normalized] == nil { names[normalized] = owner }
            for word in Self.words(in: name) where words[word] == nil {
                words[word] = owner
            }
        }

        self.vendors = vendors
        self.names = names
        self.words = words
    }

    public func evaluate(entryName: String, path: String) -> Verdict {
        let haystack = (entryName + "\n" + path).lowercased()
        if Self.iCloudMarkers.contains(where: haystack.contains) {
            return .keep("iCloud data is never touched")
        }
        if let owner = gitHubToolOwner, Self.gitHubMarkers.contains(where: haystack.contains) {
            return .keep("GitHub data is kept while \(owner) is installed")
        }
        if let owner = zapPatterns.first(where: { fnmatch($0.key, path, 0) == 0 })?.value {
            return .keep("Listed by the Homebrew cask for \(owner)")
        }

        let identifier = Self.identifier(fromFileName: entryName)
        if identifier.isEmpty || Self.isOpaque(identifier) {
            return .keep("Unidentified system item")
        }
        if Self.isBundleIdentifier(identifier) {
            return evaluate(bundleID: identifier)
        }
        return evaluate(plainName: identifier)
    }

    func evaluate(bundleID: String) -> Verdict {
        let id = bundleID.lowercased()
        if Self.systemPrefixes.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) {
            return .keep("Part of macOS")
        }
        if let owner = bundleIDs[id] {
            return .keep("Used by \(owner)")
        }
        if let owner = bundleIDs.first(where: { id.hasPrefix($0.key + ".") || $0.key.hasPrefix(id + ".") })?.value {
            return .keep("Related to \(owner)")
        }
        if let vendor = Self.vendor(of: id) {
            if Self.sharedVendors.contains(vendor) {
                return .keep("Shared framework data")
            }
            if let owner = vendors[vendor] {
                return .keep("Same developer as \(owner)")
            }
        }
        for component in id.split(separator: ".").dropFirst() {
            if let owner = names[Self.normalize(String(component))] {
                return .keep("Matches \(owner)")
            }
        }
        return .leftover(.high, "No installed app uses \(bundleID)")
    }

    func evaluate(plainName name: String) -> Verdict {
        let normalized = Self.normalize(name)
        if normalized.isEmpty
            || Self.systemNames.contains(normalized)
            || normalized.hasPrefix("apple")
            || normalized.hasPrefix("icloud")
        {
            return .keep("Part of macOS")
        }
        if Self.looksLikeSystemService(name) {
            return .keep("Looks like a macOS service")
        }
        if let owner = names[normalized] {
            return .keep("Used by \(owner)")
        }
        for word in Self.words(in: name) {
            if let owner = names[word] ?? words[word] {
                return .keep("Probably used by \(owner)")
            }
        }
        return .leftover(.low, "No installed app named “\(name)”")
    }

    // MARK: - Helpers

    static let strippedExtensions = [".plist", ".savedState", ".binarycookies", ".log"]

    /// Turns a file name into the identifier it was named after, e.g.
    /// "BQR82RBBHL.com.tinyspeck.slackmacgap" → "com.tinyspeck.slackmacgap".
    public static func identifier(fromFileName fileName: String) -> String {
        var name = fileName
        if let ext = strippedExtensions.first(where: { name.hasSuffix($0) }) {
            name.removeLast(ext.count)
        }
        if let teamID = name.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) {
            name.removeSubrange(teamID)
        }
        for prefix in ["group.", "groups."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return name
    }

    /// Reverse-DNS names like "com.vendor.App" (first label is a short lowercase TLD).
    public static func isBundleIdentifier(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let tld = parts.first, (2...6).contains(tld.count) else { return false }
        return tld.allSatisfy { $0.isASCII && $0.isLowercase }
            && !parts[1].isEmpty
            && !parts[1].contains(" ")
    }

    /// UUIDs and numeric names carry no information about their owner.
    static func isOpaque(_ identifier: String) -> Bool {
        identifier.allSatisfy(\.isNumber)
            || UUID(uuidString: identifier) != nil
    }

    /// All-lowercase daemon-style names such as "contactsd" or "icloudmailagent".
    static func looksLikeSystemService(_ name: String) -> Bool {
        name.count >= 4
            && name.allSatisfy { $0.isASCII && $0.isLowercase }
            && (name.hasSuffix("d") || name.hasSuffix("agent"))
    }

    static func vendor(of bundleID: String) -> String? {
        let parts = bundleID.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }

    static func normalize(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Significant lowercase words, split on punctuation and camelCase boundaries.
    static func words(in name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in name {
            if !(character.isLetter || character.isNumber) {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let previous, previous.isLowercase {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return
            words
            .map { $0.lowercased() }
            .filter { $0.count >= 3 && !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }
}
