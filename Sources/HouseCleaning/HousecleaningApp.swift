import AppKit
import HouseCleaningCore
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--list") {
            ListCommand.run()
        } else {
            HouseCleaningApp.main()
        }
    }
}

struct HouseCleaningApp: App {
    // Not @State: with only the Command Line Tools installed, SwiftUI's State macro plugin is unavailable.
    private let model = CleanupModel()

    init() {
        // Needed when launched as a bare executable (e.g. `swift run`) rather than an .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("HouseCleaning", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 780, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}

/// `HouseCleaning --list` prints what a scan would flag, without deleting anything.
enum ListCommand {
    static func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result = Scanner.scan(
            home: home,
            runningApps: [:],
            hasFullDiskAccess: Scanner.hasFullDiskAccess(home: home),
            progress: { _ in }
        )
        if let error = result.homebrewError {
            print("Homebrew: \(error)")
        }
        print("Apps in use: \(result.inventory.apps.count)")
        for leftover in result.leftovers {
            let confidence = leftover.confidence == .high ? "HIGH" : "low "
            let size = leftover.size.map { $0.formatted(.byteCount(style: .file)) } ?? "?"
            print(
                "\(confidence)  \(size.padding(toLength: 10, withPad: " ", startingAt: 0))  \(leftover.location)/\(leftover.url.lastPathComponent)  — \(leftover.reason)"
            )
        }
    }
}
