import Foundation
import SwiftUI
import UIKit

/// Visible, opt-in experiment control panel. No device-management profile
/// is installed automatically and no scene is activated without a tap.
struct ShellLabView: View {
    @EnvironmentObject private var lab: BerylliumShellLab
    @EnvironmentObject private var sites: SiteStore
    @EnvironmentObject private var router: BerylliumLaunchRouter
    @Environment(\.dismiss) private var dismiss

    @State private var chosenSiteID: UUID?
    @State private var profileFile: URL?
    @State private var reportFile: URL?
    @State private var message: String?
    @State private var confirmingReset = false

    private var chosenSite: WebSite? {
        if let chosenSiteID, let match = sites.sites.first(where: { $0.id == chosenSiteID }) { return match }
        return sites.sites.first
    }
    private func toggle(_ label: String, _ key: WritableKeyPath<ShellLabOptions, Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { lab.options[keyPath: key] },
            set: { value in lab.update { $0[keyPath: key] = value } }
        ))
    }
    private func optionalToggle(_ label: String, _ key: WritableKeyPath<ShellLabOptions, Bool>) -> some View {
        toggle(label, key).disabled(!lab.options.enabled)
    }
    private func setting<T>(_ key: WritableKeyPath<ShellLabOptions, T>) -> Binding<T> {
        Binding(get: { lab.options[keyPath: key] }, set: { next in lab.update { $0[keyPath: key] = next } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    toggle("Enable Shell Lab experiments", \.enabled)
                    Button("Restore stable defaults", role: .destructive) { confirmingReset = true }
                    Text("Normal Beryllium behavior is preserved until you opt in. Changes apply to NEW browser sessions; existing warm sessions may be discarded after an experiment changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Laboratory") }

                Section("Test application") {
                    if sites.sites.isEmpty {
                        Text("Add a website to Beryllium before running site tests.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Website", selection: $chosenSiteID) {
                            ForEach(sites.sites) { site in
                                Text(site.name).tag(Optional(site.id))
                            }
                        }
                        .onChange(of: chosenSiteID) { _, _ in profileFile = nil }
                        Button {
                            guard let chosenSite else { return }
                            lab.record(.launch, "Shell Lab direct-launch request for site \(chosenSite.id.uuidString)")
                            router.requestSite(chosenSite.id)
                            dismiss()
                        } label: { Label("Launch selected website", systemImage: "arrow.up.forward.app") }
                    }
                }

                Section {
                    optionalToggle("Wait for active app before launching", \.deferredShortcutLaunch)
                    optionalToggle("Coalesce duplicate incoming links", \.deduplicateShortcutLaunch)
                    Stepper("Cold-launch delay: \(lab.options.launchDelayMilliseconds) ms",
                            value: setting(\.launchDelayMilliseconds), in: 0...1500, step: 50)
                        .disabled(!lab.options.enabled)
                    Text("All launches still use one presentation path. Disable these guards only when diagnosing a device-specific launch issue.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Shortcut & cold-start routing") }

                Section {
                    optionalToggle("Allow an explicit new-scene request", \.allowSceneRequests)
                    optionalToggle("Attach a user activity to the request", \.sceneRequestWithUserActivity)
                    Button {
                        lab.captureSceneSnapshot()
                    } label: { Label("Capture scene snapshot", systemImage: "camera.metering.matrix") }
                    Button {
                        lab.requestSceneProbe(siteID: chosenSite?.id)
                    } label: { Label("Request additional native scene", systemImage: "square.on.square") }
                    .disabled(!lab.enabled(\.allowSceneRequests))
                    Text("Check the iOS App Switcher manually. An extra scene record does not guarantee another App Switcher card. iPhone may reject additional windows.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Native scene & App Switcher probe") }

                Section {
                    optionalToggle("Enable configuration-profile experiment", \.profileExperimentEnabled)
                    optionalToggle("Request full-screen Web Clip", \.profileFullScreen)
                    optionalToggle("Embed website icon in profile", \.profileIncludeIcon)
                    Picker("Profile destination", selection: setting(\.profileDestination)) {
                        ForEach(ShellLabProfileDestination.allCases) { choice in Text(choice.rawValue).tag(choice) }
                    }
                    .disabled(!lab.enabled(\.profileExperimentEnabled))
                    Button {
                        guard let chosenSite else { return }
                        do {
                            profileFile = try ShellLabProfileExporter.make(for: chosenSite, options: lab.options)
                            lab.record(.profile, "Prepared removable profile for site \(chosenSite.id.uuidString); target=\(lab.options.profileDestination.rawValue)")
                        } catch { message = error.localizedDescription }
                    } label: { Label("Generate test .mobileconfig", systemImage: "doc.badge.gearshape") }
                    .disabled(!lab.enabled(\.profileExperimentEnabled) || chosenSite == nil)
                    if let profileFile {
                        ShareLink(item: profileFile) { Label("Save/share prepared profile", systemImage: "square.and.arrow.up") }
                    }
                    Text("Install only if you choose to in iOS Settings. A Web Clip profile is not a separately signed app, and iOS may not support opening a beryllium:// URL from a profile. Test and record the outcome.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Home Screen / Web Clip profile") }

                Section {
                    optionalToggle("Retain warm website sessions", \.warmSessionsEnabled)
                    Stepper("Maximum sessions: \(lab.options.warmSessionLimit)",
                            value: setting(\.warmSessionLimit), in: 1...10)
                        .disabled(!lab.options.enabled || !lab.options.warmSessionsEnabled)
                    optionalToggle("Isolate each new site with ephemeral storage", \.ephemeralSiteIsolation)
                    Text("Ephemeral storage is independent per new website session and is not persistent across app relaunches. It may sign you out. Turn off to use normal website storage.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Discard warm sessions") {
                        WarmWebSessionPool.shared.clear()
                        lab.record(.session, "Warm session pool manually cleared")
                    }
                } header: { Text("Parallel websites & storage") }

                Section {
                    optionalToggle("Disable JavaScript in new sessions", \.suppressJavaScript)
                    optionalToggle("Disable inline video in new sessions", \.suppressInlineVideo)
                    optionalToggle("Disable swipe-back navigation", \.suppressSwipeNavigation)
                    optionalToggle("Load site extensions", \.extensionsEnabled)
                    Text("Browser overrides affect only newly created WebKit views; turn them off before ordinary browsing.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("WebKit behavior & extension variables") }

                Section {
                    optionalToggle("Show iOS status indicators", \.showStatusBar)
                    optionalToggle("Respect top Dynamic Island safe area", \.preserveTopSafeArea)
                    optionalToggle("Extend page to bottom edge", \.extendWebContentToBottom)
                    optionalToggle("Override individual website dock setting", \.dockOverrideEnabled)
                    Picker("Test dock mode", selection: setting(\.dockMode)) {
                        ForEach(ShellLabDockMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.disabled(!lab.enabled(\.dockOverrideEnabled))
                    optionalToggle("Show scene diagnostics badge on websites", \.showSceneBadge)
                    Text("Status bar defaults to visible and top safe area defaults to protected; turning those off is an intentional visual test.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Dynamic Island / status bar / dock") }

                Section("Diagnostics capture") {
                    toggle("Record diagnostic events", \.diagnosticsEnabled)
                    toggle("Log shortcut routing", \.recordLaunch)
                    toggle("Log scene requests and snapshots", \.recordScenes)
                    toggle("Log warm session changes", \.recordSessions)
                    toggle("Log new browser configurations", \.recordBrowser)
                    toggle("Log extension preparation", \.recordExtensions)
                    HStack {
                        Text("Events stored")
                        Spacer()
                        Text("\(lab.entries.count) / 250").foregroundStyle(.secondary)
                    }
                    Button { do { reportFile = try lab.prepareReport() } catch { message = error.localizedDescription } } label: {
                        Label("Prepare diagnostic report", systemImage: "doc.text.magnifyingglass")
                    }
                    if let reportFile { ShareLink(item: reportFile) { Label("Export report", systemImage: "square.and.arrow.up") } }
                    Button("Clear diagnostic history", role: .destructive) { lab.clearDiagnostics() }
                    ForEach(lab.entries.suffix(12).reversed()) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.category.rawValue + " · " + entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(entry.message).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Shell Laboratory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Restore every Shell Lab experiment setting?", isPresented: $confirmingReset) {
                Button("Restore defaults", role: .destructive) {
                    lab.resetExperiments()
                    profileFile = nil
                    reportFile = nil
                }
            } message: {
                Text("Only laboratory settings and warm sessions are reset; saved websites remain unchanged.")
            }
            .alert("Shell Lab", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
            .onAppear {
                if chosenSiteID == nil { chosenSiteID = sites.sites.first?.id }
                lab.captureSceneSnapshot()
            }
        }
    }
}
