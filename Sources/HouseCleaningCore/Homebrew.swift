import Foundation

public struct HomebrewCask: Sendable, Hashable {
    public let token: String
    public let names: [String]
    /// File names of the .app bundles the cask installs, e.g. "Visual Studio Code.app".
    public let appNames: [String]
    /// Bundle and launchd identifiers from the uninstall/zap stanzas.
    public let identifiers: [String]
    /// Absolute paths or glob patterns the cask's zap stanza would remove.
    public let zapPatterns: [String]
}

public struct HomebrewInventory: Sendable {
    /// Every installed formula name and alias, dependencies included.
    public let formulae: [String]
    /// Installed formulae no other installed formula depends on, like `brew leaves`.
    public let leaves: [String]
    public let casks: [HomebrewCask]
}

public enum Homebrew {
    public static let executableCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    public static func executable() -> URL? {
        executableCandidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Runs `brew info --installed --json=v2`. Returns nil when Homebrew is not installed.
    public static func load(home: URL) throws -> HomebrewInventory? {
        guard let brew = executable() else { return nil }

        let process = Process()
        process.executableURL = brew
        process.arguments = ["info", "--installed", "--json=v2"]
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": home.path,
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Read before waiting so a full pipe buffer can't deadlock the child.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CocoaError(
                .executableLoad,
                userInfo: [
                    NSLocalizedDescriptionKey: "brew exited with status \(process.terminationStatus)"
                ])
        }
        return try parse(data, home: home.path)
    }

    public static func parse(_ data: Data, home: String) throws -> HomebrewInventory {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var formulae: [String] = []
        var names: [String] = []
        var dependencies: Set<String> = []
        for formula in root["formulae"] as? [[String: Any]] ?? [] {
            if let name = formula["name"] as? String {
                formulae.append(name)
                names.append(name)
            }
            formulae += formula["aliases"] as? [String] ?? []
            dependencies.formUnion(formula["dependencies"] as? [String] ?? [])
            // Runtime dependencies of the installed kegs, which is what `brew leaves` goes by.
            for keg in formula["installed"] as? [[String: Any]] ?? [] {
                for dependency in keg["runtime_dependencies"] as? [[String: Any]] ?? [] {
                    if let name = dependency["full_name"] as? String { dependencies.insert(name) }
                }
            }
        }
        let leaves = names.filter { !dependencies.contains($0) }

        var casks: [HomebrewCask] = []
        for cask in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            var appNames: [String] = []
            var identifiers: [String] = []
            var zapPatterns: [String] = []

            for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
                for (kind, value) in artifact {
                    switch kind {
                    case "app":
                        appNames += strings(in: value).filter { $0.hasSuffix(".app") }
                    case "uninstall", "zap":
                        for directive in value as? [[String: Any]] ?? [] {
                            for (key, item) in directive {
                                switch key {
                                case "quit", "launchctl", "pkgutil", "signal":
                                    identifiers += strings(in: item).filter { $0.contains(".") }
                                case "trash", "delete", "rmdir":
                                    zapPatterns += strings(in: item)
                                        .filter { $0.hasPrefix("~/") }
                                        .map { home + $0.dropFirst() }
                                default:
                                    break
                                }
                            }
                        }
                    default:
                        break
                    }
                }
            }

            casks.append(
                HomebrewCask(
                    token: token,
                    names: cask["name"] as? [String] ?? [],
                    appNames: appNames.map { ($0 as NSString).lastPathComponent },
                    identifiers: identifiers,
                    zapPatterns: zapPatterns
                ))
        }

        return HomebrewInventory(formulae: formulae, leaves: leaves, casks: casks)
    }

    /// Flattens the mix of strings, arrays and nested arrays brew uses in artifact stanzas.
    private static func strings(in value: Any) -> [String] {
        switch value {
        case let string as String: [string]
        case let array as [Any]: array.flatMap { strings(in: $0) }
        default: []
        }
    }
}
