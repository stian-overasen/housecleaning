import Foundation

/// Collects the apps that count as "in use": macOS apps, App Store apps, Homebrew packages
/// and anything else installed in an Applications folder.
public enum InventoryBuilder {
    static let systemRoots = [
        "/System/Applications",
        "/System/Library/CoreServices",
        "/System/Cryptexes/App/System/Applications",
    ]

    /// Bundle types inside an app whose identifiers may show up in ~/Library.
    static let nestedBundleExtensions: Set<String> = [
        "app", "appex", "xpc", "framework", "plugin", "bundle", "systemextension",
    ]

    public static func build(
        home: URL,
        homebrew: HomebrewInventory?,
        runningApps: [String: String]
    ) -> AppInventory {
        var inventory = AppInventory()
        let casksByApp = Dictionary(
            (homebrew?.casks ?? []).flatMap { cask in cask.appNames.map { ($0.lowercased(), cask) } },
            uniquingKeysWith: { first, _ in first }
        )
        var casksWithApp: Set<String> = []
        var seenApps: Set<String> = []

        let roots = ["/Applications", home.appendingPathComponent("Applications").path] + systemRoots
        for root in roots {
            for foundURL in findApps(in: URL(fileURLWithPath: root), depth: 3) {
                // /Applications/Safari.app is a symlink into the system cryptex; classify by the real location.
                let appURL = foundURL.resolvingSymlinksInPath()
                guard seenApps.insert(appURL.path).inserted else { continue }
                let info = infoPlist(of: appURL) ?? [:]
                let fileName = appURL.deletingPathExtension().lastPathComponent
                let name =
                    info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? fileName
                let bundleID = info["CFBundleIdentifier"] as? String
                let cask = casksByApp[appURL.lastPathComponent.lowercased()]

                let source: AppSource
                if systemRoots.contains(where: { appURL.path.hasPrefix($0) })
                    || bundleID?.hasPrefix("com.apple.") == true
                {
                    source = .system
                } else if isFromAppStore(appURL) {
                    source = .appStore
                } else if let cask {
                    source = .homebrew
                    casksWithApp.insert(cask.token)
                } else {
                    source = .manual
                }

                inventory.apps.append(InstalledApp(name: name, bundleID: bundleID, source: source, url: appURL))
                inventory.addName(name, owner: name)
                inventory.addName(fileName, owner: name)
                if let bundleID { inventory.addBundleID(bundleID, owner: name) }
                if source != .system {
                    for nested in nestedBundleIDs(in: appURL) { inventory.addBundleID(nested, owner: name) }
                }
            }
        }

        for cask in homebrew?.casks ?? [] {
            let owner = cask.names.first ?? cask.token
            if !casksWithApp.contains(cask.token) {
                inventory.apps.append(InstalledApp(name: owner, bundleID: nil, source: .homebrew, url: nil))
            }
            inventory.addName(cask.token, owner: owner)
            for name in cask.names { inventory.addName(name, owner: owner) }
            for id in cask.identifiers { inventory.addBundleID(id, owner: owner) }
            for pattern in cask.zapPatterns where inventory.zapPatterns[pattern] == nil {
                inventory.zapPatterns[pattern] = owner
            }
        }

        // Dependencies still count as in use, but only leaves are listed, like `brew leaves`.
        for formula in homebrew?.formulae ?? [] {
            inventory.addName(formula, owner: formula)
        }
        for leaf in homebrew?.leaves ?? [] {
            inventory.apps.append(InstalledApp(name: leaf, bundleID: nil, source: .homebrew, url: nil))
        }
        if homebrew != nil {
            inventory.addName("Homebrew", owner: "Homebrew")
        }

        if let owner = inventory.bundleIDOwners["com.microsoft.vscode"] {
            inventory.gitHubToolOwner = owner
        } else if homebrew?.formulae.contains("gh") == true {
            inventory.gitHubToolOwner = "GitHub CLI"
        }

        for (bundleID, name) in runningApps {
            inventory.addBundleID(bundleID, owner: name)
            inventory.addName(name, owner: name)
        }

        inventory.apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return inventory
    }

    static func findApps(in directory: URL, depth: Int) -> [URL] {
        guard depth > 0,
            let items = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var apps: [URL] = []
        for item in items {
            if item.pathExtension == "app" {
                apps.append(item)
            } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                apps += findApps(in: item, depth: depth - 1)
            }
        }
        return apps
    }

    static func infoPlist(of bundle: URL) -> [String: Any]? {
        for relativePath in ["Contents/Info.plist", "Resources/Info.plist", "Info.plist"] {
            let url = bundle.appendingPathComponent(relativePath)
            if let data = try? Data(contentsOf: url),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            {
                return plist
            }
        }
        // iOS apps installed on Apple silicon keep the real bundle inside Wrapper/.
        let wrapper = bundle.appendingPathComponent("Wrapper")
        if let inner = try? FileManager.default.contentsOfDirectory(at: wrapper, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        {
            return infoPlist(of: inner)
        }
        return nil
    }

    static func isFromAppStore(_ app: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: app.appendingPathComponent("Contents/_MASReceipt").path)
            || fileManager.fileExists(atPath: app.appendingPathComponent("Wrapper/iTunesMetadata.plist").path)
    }

    static func nestedBundleIDs(in app: URL) -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: app.appendingPathComponent("Contents"),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var ids: [String] = []
        for case let url as URL in enumerator where nestedBundleExtensions.contains(url.pathExtension) {
            if let id = infoPlist(of: url)?["CFBundleIdentifier"] as? String {
                ids.append(id)
            }
        }
        return ids
    }
}
