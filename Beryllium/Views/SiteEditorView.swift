// site editor - form for adding or editing a website configuration

import SwiftUI
import PhotosUI

struct SiteEditorView: View {
    enum Mode {
        case add
        case edit(WebSite)
    }

    let mode: Mode
    @EnvironmentObject var siteStore: SiteStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlString: String = "https://"
    @State private var orientationLock: OrientationLock = .automatic
    @State private var enableJavaScript: Bool = true
    @State private var enableStikJIT: Bool = false
    @State private var allowInlineMedia: Bool = true
    @State private var enableFullScreen: Bool = false
    @State private var showNavigationDock: Bool = false
    @State private var userAgent: String = ""
    @State private var iconColorHex: String = "007AFF"
    @State private var iconSource: IconSource = .colorLetter
    @State private var showingShortcutInfo: Bool = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isFetchingFavicon: Bool = false

    // track the original site id when editing
    private var editingID: UUID? {
        if case .edit(let site) = mode { return site.id }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // basic info section
                Section {
                    TextField("site name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("url", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } header: {
                    Text("website")
                }

                // icon section - custom image, favicon, or color letter
                Section {
                    // preview of the current icon
                    HStack {
                        Spacer()
                        SiteIconView(
                            site: WebSite(
                                name: name.isEmpty ? "?" : name,
                                iconColorHex: iconColorHex,
                                iconSource: iconSource
                            ),
                            size: 80
                        )
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    // pick from photo library
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("choose from photos", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedPhoto) { newItem in
                        guard let newItem else { return }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let img = UIImage(data: data),
                               let pngData = img.pngData() {
                                iconSource = .customImage(pngData)
                            }
                        }
                    }

                    // fetch the site's favicon
                    Button {
                        fetchFavicon()
                    } label: {
                        HStack {
                            Label("Fetch browser tab icon", systemImage: "globe")
                            if isFetchingFavicon {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(urlString.count < 8 || isFetchingFavicon)

                    // reset to color letter
                    if iconSource != .colorLetter {
                        Button(role: .destructive) {
                            iconSource = .colorLetter
                            selectedPhoto = nil
                        } label: {
                            Label("remove custom icon", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("icon")
                }

                // appearance section - fallback color for when no custom icon is set
                Section {
                    Picker("fallback color", selection: $iconColorHex) {
                        Label("blue", systemImage: "circle.fill").foregroundColor(.blue).tag("007AFF")
                        Label("red", systemImage: "circle.fill").foregroundColor(.red).tag("FF3B30")
                        Label("green", systemImage: "circle.fill").foregroundColor(.green).tag("34C759")
                        Label("orange", systemImage: "circle.fill").foregroundColor(.orange).tag("FF9500")
                        Label("purple", systemImage: "circle.fill").foregroundColor(.purple).tag("AF52DE")
                        Label("pink", systemImage: "circle.fill").foregroundColor(.pink).tag("FF2D55")
                        Label("teal", systemImage: "circle.fill").foregroundColor(.teal).tag("5AC8FA")
                    }
                } header: {
                    Text("appearance")
                } footer: {
                    Text("used when no custom icon is set.")
                }

                // orientation section
                Section {
                    Picker("orientation lock", selection: $orientationLock) {
                        ForEach(OrientationLock.allCases) { lock in
                            Text(lock.displayName).tag(lock)
                        }
                    }
                } header: {
                    Text("orientation")
                } footer: {
                    Text("force the web container to a specific orientation, or let it rotate automatically.")
                }

                // behavior section
                Section {
                    Toggle("javascript", isOn: $enableJavaScript)
                    Toggle("inline media playback", isOn: $allowInlineMedia)
                    Toggle("full screen mode", isOn: $enableFullScreen)
                    Toggle("show bottom navigation dock", isOn: $showNavigationDock)
                } header: {
                    Text("behavior")
                } footer: {
                    Text("full screen hides the status bar and navigation controls for an immersive experience.")
                }

                // advanced section
                Section {
                    Toggle("enable stikjit", isOn: $enableStikJIT)
                } header: {
                    Text("jit")
                } footer: {
                    Text("enables stikjit for apps that need just-in-time compilation. requires stikjit to be installed and running on device.")
                }

                // custom user agent
                Section {
                    TextField("custom user agent (optional)", text: $userAgent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("advanced")
                } footer: {
                    Text("override the default user agent string. leave empty to use the default webkit user agent.")
                }

                // Per-site extension settings are managed here and in the app manager.
                if let existingID = editingID {
                    SiteExtensionsView(siteID: existingID)
                }

                // home screen shortcut section
                Section {
                    Button {
                        showingShortcutInfo = true
                    } label: {
                        Label("add to home screen", systemImage: "plus.square.on.square")
                    }
                } header: {
                    Text("shortcut")
                } footer: {
                    Text("creates a home screen shortcut that opens this site directly in the beryllium container.")
                }
            }
            .navigationTitle(editingID == nil ? "add site" : "edit site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") { saveSite() }
                        .disabled(name.isEmpty || urlString.count < 8)
                }
            }
            .alert("add to home screen", isPresented: $showingShortcutInfo) {
                Button("ok") {}
            } message: {
                Text("Save this site first, then use Create Home Screen Shortcut in App Manager. Beryllium opens the native Shortcuts editor instead of Safari.")
            }
            .onAppear {
                if case .edit(let site) = mode {
                    name = site.name
                    urlString = site.urlString
                    orientationLock = site.orientationLock
                    enableJavaScript = site.enableJavaScript
                    enableStikJIT = site.enableStikJIT
                    allowInlineMedia = site.allowInlineMedia
                    enableFullScreen = site.enableFullScreen
                    showNavigationDock = site.navigationDockEnabled
                    userAgent = site.userAgent
                    iconColorHex = site.iconColorHex
                    iconSource = site.iconSource
                }
            }
        }
    }

    // build a website from current form state and persist it
    private func saveSite() {
        let site = WebSite(
            id: editingID ?? UUID(),
            name: name,
            urlString: urlString,
            orientationLock: orientationLock,
            enableJavaScript: enableJavaScript,
            enableStikJIT: enableStikJIT,
            allowInlineMedia: allowInlineMedia,
            enableFullScreen: enableFullScreen,
            showNavigationDock: showNavigationDock,
            userAgent: userAgent,
            iconColorHex: iconColorHex,
            iconSource: iconSource
        )

        if editingID != nil {
            siteStore.update(site)
        } else {
            siteStore.add(site)
        }
        dismiss()
    }

    // Get the exact browser-tab favicon from the page's <link rel="icon">.
    private func fetchFavicon() {
        guard let url = URL(string: urlString) else { return }
        isFetchingFavicon = true
        Task {
            let result = try? await SiteFaviconResolver.fetch(for: url)
            await MainActor.run {
                if let result { iconSource = .customImage(result) }
                isFetchingFavicon = false
            }
        }
    }

}
