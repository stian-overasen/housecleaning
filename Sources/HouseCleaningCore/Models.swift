import Foundation

/// Where an installed app came from.
public enum AppSource: String, Sendable, CaseIterable {
    case system = "macOS"
    case appStore = "App Store"
    case homebrew = "Homebrew"
    case manual = "Manually installed"
}

public struct InstalledApp: Sendable, Hashable, Identifiable {
    public var id: String { "\(source.rawValue)|\(url?.path ?? name)" }
    public let name: String
    public let bundleID: String?
    public let source: AppSource
    public let url: URL?

    public init(name: String, bundleID: String?, source: AppSource, url: URL?) {
        self.name = name
        self.bundleID = bundleID
        self.source = source
        self.url = url
    }
}

public enum Confidence: Sendable, Hashable {
    /// Entry carries a bundle identifier that no installed app uses.
    case high
    /// Entry is a plain name that could not be matched to anything.
    case low
}

/// A file or folder in ~/Library that appears to belong to an app that is no longer installed.
public struct Leftover: Sendable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let location: String
    public let confidence: Confidence
    public let reason: String
    /// Allocated size in bytes, or nil when it could not be measured without Full Disk Access.
    public let size: Int64?

    public init(url: URL, location: String, confidence: Confidence, reason: String, size: Int64?) {
        self.url = url
        self.location = location
        self.confidence = confidence
        self.reason = reason
        self.size = size
    }
}

/// Everything that counts as "in use", keyed for matching.
public struct AppInventory: Sendable {
    public var apps: [InstalledApp] = []
    /// Lowercased bundle identifier → name of the app that owns it.
    public var bundleIDOwners: [String: String] = [:]
    /// Raw name (app name, cask token, formula name) → owner name.
    public var nameOwners: [String: String] = [:]
    /// Absolute glob pattern from a Homebrew cask zap stanza → cask name.
    public var zapPatterns: [String: String] = [:]
    /// Name of an installed GitHub tool (VS Code or the gh CLI), which protects GitHub data.
    public var gitHubToolOwner: String?

    public init() {}

    public mutating func addBundleID(_ id: String, owner: String) {
        let key = Matcher.identifier(fromFileName: id).lowercased()
        guard !key.isEmpty, bundleIDOwners[key] == nil else { return }
        bundleIDOwners[key] = owner
    }

    public mutating func addName(_ name: String, owner: String) {
        guard !name.isEmpty, nameOwners[name] == nil else { return }
        nameOwners[name] = owner
    }
}
