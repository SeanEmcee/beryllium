import SwiftUI
import UniformTypeIdentifiers

struct SiteExtensionsView: View {
    let siteID: UUID
    @ObservedObject private var library = ExtensionLibrary.shared
    @State private var importingKind: ExtensionKind = .chromium
    @State private var showImporter = false
    @State private var staged: StagedExtension?
    @State private var alertMessage: String?

    var body: some View {
        ForEach(ExtensionKind.allCases) { kind in
            Section {
                ForEach(library.installed(kind: kind)) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                            Text("Version \(entry.version)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Toggle(entry.name, isOn: Binding(
                            get: { library.enabled(entry, siteID: siteID) },
                            set: { library.setEnabled($0, entry: entry, siteID: siteID) }
                        )).labelsHidden()
                    }
                    .contextMenu {
                        Button(role: .destructive) { library.uninstall(entry) } label: {
                            Label("Uninstall extension from all apps", systemImage: "trash")
                        }
                    }
                }
                Button {
                    importingKind = kind
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Import \(kind.rawValue)")
            } header: {
                Text(kind.rawValue)
            } footer: {
                if kind == .chromium {
                    Text("Import compatible Chrome/Firefox WebExtension ZIPs. Full Chromium API compatibility is not available.")
                } else {
                    Text("Import Safari-compatible WebExtension ZIPs. Extensions installed in Safari by other apps cannot be imported automatically.")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do { staged = try await library.stage(sourceURL: url, kind: importingKind) }
                    catch { alertMessage = error.localizedDescription }
                }
            case .failure(let error): alertMessage = error.localizedDescription
            }
        }
        .alert("Extension Import Error", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
        .sheet(item: $staged) { package in
            NavigationStack {
                Form {
                    Section("Extension") {
                        Text(package.entry.name).font(.headline)
                        Text("Version \(package.entry.version)")
                        Text(package.entry.kind.rawValue)
                    }
                    Section("Requested API permissions") {
                        if package.entry.requestedPermissions.isEmpty { Text("None") }
                        ForEach(package.entry.requestedPermissions, id: \.self) { Text($0) }
                    }
                    Section("Requested website access") {
                        if package.entry.requestedHosts.isEmpty { Text("None") }
                        ForEach(package.entry.requestedHosts, id: \.self) { Text($0) }
                    }
                    Section {
                        Text("Only install extension packages you trust. Granting these requested permissions may allow the extension to read or modify matching websites. Unsupported Chromium APIs may not work.")
                            .font(.footnote)
                    }
                }
                .navigationTitle("Review extension")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { library.cancel(package); staged = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Install & Allow") {
                            do { try library.confirm(package, for: siteID) }
                            catch { alertMessage = error.localizedDescription }
                            staged = nil
                        }
                    }
                }
            }
        }
    }
}
