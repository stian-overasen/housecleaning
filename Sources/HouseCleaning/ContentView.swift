import HouseCleaningCore
import SwiftUI

struct ContentView: View {
    @Environment(CleanupModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            if !model.hasFullDiskAccess {
                FullDiskAccessBanner()
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .fixedSize(horizontal: false, vertical: true)
        }
        .searchable(text: $model.searchText, prompt: "Search paths")
        .toolbar {
            ToolbarItemGroup {
                Button(
                    model.showLowConfidence ? "Hide Uncertain" : "Show Uncertain",
                    systemImage: model.showLowConfidence ? "eye.slash" : "eye"
                ) {
                    model.showLowConfidence.toggle()
                }
                .labelStyle(.titleAndIcon)
                .help("Folders that only have a plain name and could not be matched with certainty")
                Button("Apps in Use", systemImage: "square.grid.2x2") { model.showingApps = true }
                    .disabled(model.apps.isEmpty)
                Button("Scan", systemImage: "arrow.clockwise") { Task { await model.scan() } }
                    .disabled(model.isScanning)
            }
        }
        .task {
            if model.phase == .idle { await model.scan() }
        }
        .sheet(isPresented: $model.showingApps) {
            AppsInUseView()
        }
        .alert(
            "Move \(model.selectedVisible.count) items to the Trash?",
            isPresented: $model.confirmingTrash
        ) {
            Button("Move to Trash", role: .destructive) { model.trashSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(model.selectedSize.formatted(.byteCount(style: .file))) will be moved to the Trash. You can restore the items from the Trash until you empty it."
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label("HouseCleaning", systemImage: "sparkles")
            } description: {
                Text("Find files in your Library folder left behind by apps that are no longer installed.")
            } actions: {
                Button("Scan") { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        case .scanning(let message):
            ProgressView(message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .finished where model.visibleLeftovers.isEmpty && !model.searchText.isEmpty:
            ContentUnavailableView.search(text: model.searchText)
        case .finished where model.visibleLeftovers.isEmpty:
            ContentUnavailableView(
                "Nothing to Clean",
                systemImage: "checkmark.seal",
                description: Text("No leftovers from uninstalled apps were found.")
            )
        case .finished:
            List {
                ForEach(model.groups, id: \.location) { group in
                    Section {
                        ForEach(group.items) { leftover in
                            LeftoverRow(leftover: leftover)
                        }
                    } header: {
                        SectionHeader(location: group.location, items: group.items)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.phase == .finished {
                Button("Select All") { model.setSelected(true, for: model.visibleLeftovers) }
                Button("Select None") { model.setSelected(false, for: model.visibleLeftovers) }
                Text(
                    "\(model.selectedVisible.count) selected · \(model.selectedSize.formatted(.byteCount(style: .file)))"
                )
                .foregroundStyle(.secondary)
                .monospacedDigit()
                if model.hiddenSelectionCount > 0 {
                    Text("(\(model.hiddenSelectionCount) more selected outside the search, not affected)")
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Move to Trash…", systemImage: "trash", role: .destructive) { model.confirmingTrash = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedVisible.isEmpty || model.isScanning)
        }
        .padding(10)
    }
}

struct LeftoverRow: View {
    @Environment(CleanupModel.self) private var model
    let leftover: Leftover

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(
                isOn: Binding(
                    get: { model.selection.contains(leftover.url) },
                    set: { _ in model.toggle(leftover) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leftover.url.path)
                    Text(leftover.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()

            if leftover.confidence == .low {
                Text("Uncertain")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .help("Plain folder name with no matching app. Check it before deleting.")
            }
            Text(leftover.size.map { $0.formatted(.byteCount(style: .file)) } ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Button("Reveal in Finder", systemImage: "magnifyingglass") { model.reveal(leftover) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .contextMenu {
            Button("Reveal in Finder") { model.reveal(leftover) }
        }
    }
}

struct SectionHeader: View {
    @Environment(CleanupModel.self) private var model
    let location: String
    let items: [Leftover]

    var body: some View {
        let size = items.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        HStack {
            Text(location)
            Text("\(items.count) items · \(size.formatted(.byteCount(style: .file)))")
                .foregroundStyle(.secondary)
                .fontWeight(.regular)
            Spacer()
            Button("Select All") { model.setSelected(true, for: items) }
            Button("Select None") { model.setSelected(false, for: items) }
        }
        .buttonStyle(.link)
        .controlSize(.small)
    }
}

struct FullDiskAccessBanner: View {
    @Environment(CleanupModel.self) private var model

    var body: some View {
        HStack {
            Image(systemName: "lock.shield")
            Text("Without Full Disk Access, app containers can't be measured and some leftovers are skipped.")
                .font(.callout)
            Spacer()
            Button("Open Settings") { model.openFullDiskAccessSettings() }
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .background(.yellow.opacity(0.15))
    }
}

struct AppsInUseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CleanupModel.self) private var model

    private var apps: [InstalledApp] { model.apps }

    private var filtered: [InstalledApp] {
        model.appSourceFilter.map { source in apps.filter { $0.source == source } } ?? apps
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading) {
            Picker("Source", selection: $model.appSourceFilter) {
                Text("All (\(apps.count))").tag(AppSource?.none)
                ForEach(AppSource.allCases, id: \.self) { source in
                    Text("\(source.rawValue) (\(apps.filter { $0.source == source }.count))")
                        .tag(AppSource?.some(source))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Table(filtered) {
                TableColumn("Name", value: \.name)
                TableColumn("Source", value: \.source.rawValue)
                TableColumn("Bundle ID") { app in Text(app.bundleID ?? "—") }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 440)
    }
}
