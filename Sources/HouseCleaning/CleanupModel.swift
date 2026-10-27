import AppKit
import HouseCleaningCore
import Observation

@MainActor
@Observable
final class CleanupModel {
    enum Phase: Equatable {
        case idle
        case scanning(String)
        case finished
    }

    let home = FileManager.default.homeDirectoryForCurrentUser

    var phase: Phase = .idle
    var leftovers: [Leftover] = []
    var selection: Set<URL> = []
    var apps: [InstalledApp] = []
    var hasFullDiskAccess = false
    var notice: String?
    var confirmingTrash = false
    var showingApps = false
    var appSourceFilter: AppSource?
    var searchText = ""
    var showLowConfidence = true {
        didSet {
            if !showLowConfidence {
                selection.subtract(leftovers.filter { $0.confidence == .low }.map(\.url))
            }
        }
    }

    var visibleLeftovers: [Leftover] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return leftovers.filter { leftover in
            (showLowConfidence || leftover.confidence == .high)
                && (query.isEmpty
                    || leftover.url.path.localizedCaseInsensitiveContains(query)
                    || leftover.reason.localizedCaseInsensitiveContains(query))
        }
    }

    var groups: [(location: String, items: [Leftover])] {
        Dictionary(grouping: visibleLeftovers, by: \.location)
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { (location: $0.key, items: $0.value) }
    }

    /// Selected items that are currently visible. Only these are moved to the Trash.
    var selectedVisible: [Leftover] {
        visibleLeftovers.filter { selection.contains($0.url) }
    }

    /// Selected items hidden by the search or the uncertain filter; they are left alone.
    var hiddenSelectionCount: Int {
        selection.count - selectedVisible.count
    }

    var selectedSize: Int64 {
        selectedVisible.reduce(0) { $0 + ($1.size ?? 0) }
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    init() {
        hasFullDiskAccess = Scanner.hasFullDiskAccess(home: home)
    }

    func scan() async {
        guard !isScanning else { return }
        hasFullDiskAccess = Scanner.hasFullDiskAccess(home: home)
        notice = nil
        phase = .scanning("Starting…")

        var running: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { running[id] = app.localizedName ?? id }
        }
        if let ownID = Bundle.main.bundleIdentifier { running[ownID] = "HouseCleaning" }

        let home = self.home
        let fullDiskAccess = hasFullDiskAccess
        let result = await Task.detached(priority: .userInitiated) {
            Scanner.scan(home: home, runningApps: running, hasFullDiskAccess: fullDiskAccess) { message in
                Task { @MainActor in
                    if self.isScanning { self.phase = .scanning(message) }
                }
            }
        }.value

        apps = result.inventory.apps
        leftovers = result.leftovers.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
        selection = Set(leftovers.filter { $0.confidence == .high }.map(\.url))
        if let error = result.homebrewError {
            notice = "Could not read Homebrew packages: \(error)"
        }
        phase = .finished
    }

    func toggle(_ leftover: Leftover) {
        if selection.contains(leftover.url) {
            selection.remove(leftover.url)
        } else {
            selection.insert(leftover.url)
        }
    }

    func setSelected(_ selected: Bool, for items: [Leftover]) {
        let urls = items.map(\.url)
        if selected {
            selection.formUnion(urls)
        } else {
            selection.subtract(urls)
        }
    }

    func reveal(_ leftover: Leftover) {
        NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
    }

    func trashSelected() {
        var trashed: Set<URL> = []
        var failed: [String] = []
        // Defensive re-check: iCloud data must never be moved, whatever the scan said.
        for url in selectedVisible.map(\.url) where !Scanner.isInICloud(url) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.insert(url)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        leftovers.removeAll { trashed.contains($0.url) }
        selection.subtract(trashed)

        notice = "Moved \(trashed.count) item\(trashed.count == 1 ? "" : "s") to the Trash."
        if !failed.isEmpty {
            notice! += " Could not move: \(failed.sorted().joined(separator: ", "))."
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
