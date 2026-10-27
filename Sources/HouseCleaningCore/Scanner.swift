import Foundation

public struct ScanLocation: Sendable {
    public let name: String
    public let url: URL
    /// Reading inside this location needs Full Disk Access to avoid per-app privacy prompts.
    public let isProtected: Bool
}

public struct ScanResult: Sendable {
    public let inventory: AppInventory
    public let leftovers: [Leftover]
    public let homebrewError: String?
}

public enum Scanner {
    public static func locations(home: URL) -> [ScanLocation] {
        let library = home.appendingPathComponent("Library")
        let protected: Set<String> = ["Containers", "Group Containers"]
        return [
            "Application Support", "Caches", "Preferences", "Containers", "Group Containers",
            "Application Scripts", "Saved Application State", "Logs", "HTTPStorages", "WebKit",
            "Cookies", "LaunchAgents",
        ].map {
            ScanLocation(name: $0, url: library.appendingPathComponent($0), isProtected: protected.contains($0))
        }
    }

    /// The Safari folder is only readable with Full Disk Access, which makes it a cheap probe.
    public static func hasFullDiskAccess(home: URL) -> Bool {
        let probe = home.appendingPathComponent("Library/Safari").path
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    public static func scan(
        home: URL,
        runningApps: [String: String],
        hasFullDiskAccess: Bool,
        progress: @Sendable (String) -> Void
    ) -> ScanResult {
        progress("Reading Homebrew packages…")
        var homebrewError: String?
        var homebrew: HomebrewInventory?
        do {
            homebrew = try Homebrew.load(home: home)
        } catch {
            homebrewError = error.localizedDescription
        }

        progress("Finding installed apps…")
        let inventory = InventoryBuilder.build(home: home, homebrew: homebrew, runningApps: runningApps)
        let matcher = Matcher(inventory: inventory)

        var leftovers: [Leftover] = []
        for location in locations(home: home) {
            progress("Scanning \(location.name)…")
            guard
                let entries = try? FileManager.default.contentsOfDirectory(
                    at: location.url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            else { continue }

            let canReadInside = hasFullDiskAccess || !location.isProtected
            for entry in entries {
                if isInICloud(entry) { continue }
                var name = entry.lastPathComponent
                // Some sandboxed extensions get UUID-named containers; the real ID is in the metadata.
                if location.name == "Containers", UUID(uuidString: name) != nil {
                    guard canReadInside, let id = containerIdentifier(entry) else { continue }
                    name = id
                }

                guard case let .leftover(confidence, reason) = matcher.evaluate(entryName: name, path: entry.path)
                else { continue }

                leftovers.append(
                    Leftover(
                        url: entry,
                        location: location.name,
                        confidence: confidence,
                        reason: reason,
                        size: canReadInside ? size(of: entry) : nil
                    ))
            }
        }

        return ScanResult(inventory: inventory, leftovers: leftovers, homebrewError: homebrewError)
    }

    /// True for items stored in or synced through iCloud Drive.
    public static func isInICloud(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem == true
            || url.resolvingSymlinksInPath().path.contains("/Library/Mobile Documents")
    }

    static func containerIdentifier(_ container: URL) -> String? {
        let metadata = container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let data = try? Data(contentsOf: metadata),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["MCMMetadataIdentifier"] as? String
    }

    /// Allocated size on disk, without following symlinks.
    public static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }

        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                errorHandler: { _, _ in true }
            )
        else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
