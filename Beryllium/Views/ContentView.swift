// content view - main screen showing the list of configured websites

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var siteStore: SiteStore
    @EnvironmentObject private var appearance: BerylliumAppearance
    @EnvironmentObject private var launchRouter: BerylliumLaunchRouter
    @EnvironmentObject private var shellLab: BerylliumShellLab
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddSite = false
    @State private var showingAppearanceSettings = false
    @State private var selectedSite: WebSite?
    @State private var managingSite: WebSite?
    @State private var siteToShare: WebSite?
    @State private var isDashboardReady = false
    @State private var shortcutIssue: String?
    @State private var showingShellLab = false

    var body: some View {
        NavigationStack {
            Group {
                if siteStore.sites.isEmpty {
                    // empty state when no sites have been added yet
                    VStack(spacing: 16) {
                        Image(systemName: "globe")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        BerylliumStyledText(value: "No websites yet", area: .emptyTitle)
                        BerylliumStyledText(value: "tap + to wrap a website into an app", area: .emptyDetail)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(siteStore.sites) { site in
                            SiteRow(site: site)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    managingSite = site
                                }
                                .contextMenu {
                                    Button {
                                        siteToShare = site
                                    } label: {
                                        Label("add to home screen", systemImage: "square.and.arrow.up")
                                    }
                                }
                        }
                        .onDelete(perform: siteStore.remove)
                    }
                }
            }
            .navigationTitle("Beryllium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Interface", selection: $appearance.mode) {
                            ForEach(BerylliumAppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Divider()
                        Button {
                            showingAppearanceSettings = true
                        } label: {
                            Label("Text Colors & Gradients", systemImage: "paintbrush.pointed.fill")
                        }
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 17, weight: .medium))
                            .accessibilityLabel("Theme selector")
                    }
                }
                ToolbarItem(placement: .principal) {
                    BerylliumWordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { showingShellLab = true } label: {
                            Image(systemName: "flask.fill")
                        }
                        .accessibilityLabel("Shell Laboratory")
                        Button { showingAddSite = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingShellLab, onDismiss: schedulePendingShortcut) {
                ShellLabView()
            }
            .sheet(isPresented: $showingAppearanceSettings, onDismiss: schedulePendingShortcut) {
                AppearanceSettingsView()
            }
            .sheet(isPresented: $showingAddSite, onDismiss: schedulePendingShortcut) {
                SiteEditorView(mode: .add)
                    .environmentObject(siteStore)
            }
            .sheet(item: $managingSite, onDismiss: schedulePendingShortcut) { site in
                SiteManagerView(site: site) { selected in
                    managingSite = nil
                    // Avoid presenting the full-screen cover while the sheet
                    // is still being dismissed.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        selectedSite = selected
                    }
                }
                .environmentObject(siteStore)
            }
            .fullScreenCover(item: $selectedSite, onDismiss: schedulePendingShortcut) { site in
                WebContainerView(site: site)
            }
            .sheet(item: $siteToShare, onDismiss: schedulePendingShortcut) { site in
                AddToHomeScreenView(site: site)
            }
            .task {
                isDashboardReady = true
                schedulePendingShortcut()
            }
            .onReceive(launchRouter.$pendingSiteID) { identifier in
                if identifier != nil { schedulePendingShortcut() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { schedulePendingShortcut() }
            }
            .alert("Shortcut unavailable", isPresented: Binding(
                get: { shortcutIssue != nil },
                set: { if !$0 { shortcutIssue = nil } }
            )) {
                Button("OK", role: .cancel) { shortcutIssue = nil }
            } message: {
                Text(shortcutIssue ?? "")
            }
        }
    }

    // Delay cold-start deep links until the window has activated. The same
    // selectedSite cover is used for normal site taps and Shortcuts launches.
    private func schedulePendingShortcut() {
        guard isDashboardReady, launchRouter.pendingSiteID != nil else { return }
        Task { @MainActor in
            let duration = shellLab.options.enabled ? shellLab.options.launchDelayMilliseconds : 450
            try? await Task.sleep(for: .milliseconds(duration))
            presentPendingShortcutIfReady()
        }
    }

    private func presentPendingShortcutIfReady() {
        guard isDashboardReady,
              (scenePhase == .active || (shellLab.options.enabled && !shellLab.options.deferredShortcutLaunch)),
              selectedSite == nil, managingSite == nil, siteToShare == nil,
              !showingAddSite, !showingAppearanceSettings, !showingShellLab,
              let identifier = launchRouter.pendingSiteID else { return }

        // Consume first so overlapping activation events cannot present twice.
        launchRouter.consume(identifier)
        guard let requested = siteStore.sites.first(where: { $0.id == identifier }) else {
            shortcutIssue = "This shortcut points to a website that is not in Beryllium's saved apps. Open Beryllium, recreate the website if needed, and generate a new shortcut."
            return
        }
        shellLab.record(.launch, "Presenting site \(identifier.uuidString) on shared dashboard")
        selectedSite = requested
    }

}

// row view for a single site in the list
struct SiteRow: View {
    @EnvironmentObject private var appearance: BerylliumAppearance
    let site: WebSite

    var body: some View {
        HStack(spacing: 12) {
            // site icon - either custom image or colored letter fallback
            SiteIconView(site: site, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                BerylliumStyledText(value: site.name, area: .siteName)
                    .lineLimit(1)
                BerylliumStyledText(value: site.urlString, area: .siteURL)
                    .opacity(0.67)
                    .lineLimit(1)
            }

            Spacer()

            // orientation indicator
            Image(systemName: orientationIcon)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var orientationIcon: String {
        switch site.orientationLock {
        case .portrait: return "iphone"
        case .landscape: return "iphone.landscape"
        case .automatic: return "arrow.triangle.2.circlepath"
        }
    }
}

// reusable icon view that renders the correct icon type for a site
struct SiteIconView: View {
    let site: WebSite
    let size: CGFloat

    var body: some View {
        Group {
            if let image = site.iconSource.uiImage {
                // custom or favicon image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else {
                // fallback: colored square with first letter
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(Color(hex: site.iconColorHex) ?? .blue)
                        .frame(width: size, height: size)
                    Text(String(site.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

// hex color extension for the icon colors
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b)
    }
}
