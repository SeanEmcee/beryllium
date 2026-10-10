import SwiftUI
import UIKit

// App details open first on tapping an existing shortcut in the dashboard.
struct SiteManagerView: View {
    let site: WebSite
    let launch: (WebSite) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var siteStore: SiteStore
    @State private var showEditor = false
    @State private var showHomeScreen = false

    private var currentSite: WebSite {
        siteStore.sites.first(where: { $0.id == site.id }) ?? site
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Application") {
                    HStack(spacing: 14) {
                        SiteIconView(site: currentSite, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentSite.name).font(.headline)
                            Text(currentSite.urlString).font(.caption)
                                .foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Button { dismiss(); launch(currentSite) } label: {
                        Label("Open Application", systemImage: "arrow.up.forward.app.fill")
                    }
                    Button { showEditor = true } label: {
                        Label("Edit Name, URL, Icon & Settings", systemImage: "slider.horizontal.3")
                    }
                    Button { showHomeScreen = true } label: {
                        Label("Create Home Screen Shortcut", systemImage: "plus.app")
                    }
                    Button {
                        UIPasteboard.general.string = "beryllium://open?id=\(currentSite.id.uuidString)"
                    } label: {
                        Label("Copy Direct Launch URL", systemImage: "link")
                    }
                }
                Section("Browser appearance") {
                    Toggle("Show bottom navigation dock", isOn: Binding(
                        get: { currentSite.navigationDockEnabled },
                        set: { enabled in
                            var updated = currentSite
                            updated.showNavigationDock = enabled
                            siteStore.update(updated)
                        }
                    ))
                    Text("When hidden, triple-tap the page to show navigation temporarily. Extensions still have their own bottom-center button.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SiteExtensionsView(siteID: site.id)
            }
            .navigationTitle("App Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showEditor) {
                SiteEditorView(mode: .edit(currentSite)).environmentObject(siteStore)
            }
            .sheet(isPresented: $showHomeScreen) {
                AddToHomeScreenView(site: currentSite)
            }
        }
    }
}
