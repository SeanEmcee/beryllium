import SwiftUI
import UniformTypeIdentifiers

struct SiteExtensionsView: View {
    let siteID: UUID
    @ObservedObject private var library = ExtensionLibrary.shared
    @State private var importingKind: ExtensionKind = .chromium
    @State private var showImporter = false
    @State private var browsingKind: ExtensionKind?
    @State private var showURLPrompt = false
    @State private var remoteZipURL = ""
    @State private var isDownloading = false
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
                Menu {
                    Button("Search extension store", systemImage: "magnifyingglass") {
                        browsingKind = kind
                    }
                    Button("Install from HTTPS ZIP URL", systemImage: "link") {
                        importingKind = kind
                        remoteZipURL = ""
                        showURLPrompt = true
                    }
                    Button("Import ZIP from Files", systemImage: "square.and.arrow.down") {
                        importingKind = kind
                        showImporter = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("Manage \(kind.rawValue)")
            } header: {
                Text(kind.rawValue)
            } footer: {
                if kind == .chromium {
                    Text("Browse the Chrome Web Store, or import a compatible package via its HTTPS ZIP URL. The store Add button is not supported by iOS WebKit.")
                } else {
                    Text("Browse Safari extensions; install compatible standalone WebExtension ZIPs by URL or Files. Other iOS apps’ Safari extensions cannot be transferred.")
                }
            }
        }
        .sheet(item: $browsingKind) { kind in
            ExtensionMarketplaceView(kind: kind)
        }
        .alert("Install Extension Package", isPresented: $showURLPrompt) {
            TextField("https://example.org/extension.zip", text: $remoteZipURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { }
            Button("Download & Review") {
                let urlText = remoteZipURL
                let kind = importingKind
                Task { await downloadPackage(urlText, kind: kind) }
            }
        } message: {
            Text("Only direct HTTPS links to trusted, portable WebExtension ZIP packages are supported. You'll review permissions before installation.")
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

    @MainActor private func downloadPackage(_ raw: String, kind: ExtensionKind) async {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else {
            alertMessage = "Enter a direct HTTPS ZIP download URL."
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (downloaded, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.url?.scheme?.lowercased() == "https" else {
                throw ExtensionError.invalid("The extension download failed or redirected away from HTTPS.")
            }
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".zip")
            try FileManager.default.copyItem(at: downloaded, to: temp)
            defer { try? FileManager.default.removeItem(at: temp) }
            staged = try await library.stage(sourceURL: temp, kind: kind)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
