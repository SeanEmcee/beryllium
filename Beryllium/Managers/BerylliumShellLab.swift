import Foundation
import SwiftUI
import UIKit

enum ShellLabDockMode: String, CaseIterable, Identifiable, Codable {
    case websiteSetting = "Website setting"
    case alwaysShown = "Always shown"
    case gestureOnly = "Triple-tap to show"
    case completelyDisabled = "Completely disabled"
    var id: String { rawValue }
}

enum ShellLabProfileDestination: String, CaseIterable, Identifiable, Codable {
    case deepLink = "Beryllium deep link"
    case website = "Website URL (control)"
    var id: String { rawValue }
}

enum ShellLabLogCategory: String, CaseIterable, Codable {
    case launch = "Launch"
    case scene = "Scene"
    case session = "Session"
    case browser = "Browser"
    case extensionLoad = "Extensions"
    case profile = "Profile"
}

// All experiments are off or use Beryllium's existing settings by default.
// Explicit opt-in is needed for risky behavior. Settings persist between runs.
struct ShellLabOptions: Codable, Equatable {
    var enabled = false
    var showStatusBar = true
    var preserveTopSafeArea = true
    var extendWebContentToBottom = true
    var dockOverrideEnabled = false
    var dockMode = ShellLabDockMode.websiteSetting
    var showSceneBadge = false

    var deferredShortcutLaunch = true
    var deduplicateShortcutLaunch = true
    var launchDelayMilliseconds = 450

    var allowSceneRequests = false
    var sceneRequestWithUserActivity = false
    var profileExperimentEnabled = false
    var profileFullScreen = false
    var profileIncludeIcon = true
    var profileDestination = ShellLabProfileDestination.deepLink

    var warmSessionsEnabled = true
    var warmSessionLimit = 2
    var ephemeralSiteIsolation = false
    var suppressJavaScript = false
    var suppressInlineVideo = false
    var suppressSwipeNavigation = false
    var extensionsEnabled = true

    var diagnosticsEnabled = true
    var recordLaunch = true
    var recordScenes = true
    var recordSessions = true
    var recordBrowser = true
    var recordExtensions = true
}

struct ShellLabLogEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let category: ShellLabLogCategory
    let message: String
}

@MainActor
final class BerylliumShellLab: ObservableObject {
    static let shared = BerylliumShellLab()
    private static let optionsKey = "Beryllium.ShellLab.v6.options"
    private static let logsKey = "Beryllium.ShellLab.v6.logs"
    @Published private(set) var options: ShellLabOptions {
        didSet { persistOptions() }
    }
    @Published private(set) var entries: [ShellLabLogEntry] {
        didSet { persistEntries() }
    }

    private init() {
        let defaults = UserDefaults.standard
        options = defaults.data(forKey: Self.optionsKey)
            .flatMap { try? JSONDecoder().decode(ShellLabOptions.self, from: $0) } ?? ShellLabOptions()
        entries = defaults.data(forKey: Self.logsKey)
            .flatMap { try? JSONDecoder().decode([ShellLabLogEntry].self, from: $0) } ?? []
    }

    func update(_ operation: (inout ShellLabOptions) -> Void) {
        var next = options
        operation(&next)
        next.warmSessionLimit = min(10, max(1, next.warmSessionLimit))
        next.launchDelayMilliseconds = min(1500, max(0, next.launchDelayMilliseconds))
        options = next
    }

    func enabled(_ option: KeyPath<ShellLabOptions, Bool>) -> Bool {
        options.enabled && options[keyPath: option]
    }

    func record(_ category: ShellLabLogCategory, _ message: String) {
        guard options.diagnosticsEnabled else { return }
        let selected: Bool
        switch category {
        case .launch: selected = options.recordLaunch
        case .scene: selected = options.recordScenes
        case .session: selected = options.recordSessions
        case .browser: selected = options.recordBrowser
        case .extensionLoad: selected = options.recordExtensions
        case .profile: selected = true
        }
        guard selected else { return }
        entries.append(ShellLabLogEntry(category: category, message: message))
        if entries.count > 250 { entries.removeFirst(entries.count - 250) }
    }

    func resetExperiments() {
        options = ShellLabOptions()
        record(.session, "Reset experiment settings to stable defaults")
        WarmWebSessionPool.shared.clear()
    }

    func clearDiagnostics() { entries = [] }

    func captureSceneSnapshot() {
        let scenes = UIApplication.shared.connectedScenes
        let sessions = UIApplication.shared.openSessions
        record(.scene, "Connected scenes: \(scenes.count), registered sessions: \(sessions.count)")
        for scene in scenes {
            guard let window = scene as? UIWindowScene else { continue }
            record(.scene, "Scene \(window.session.persistentIdentifier.prefix(16)), state=\(window.activationState.rawValue), windows=\(window.windows.count), role=\(window.session.role.rawValue)")
        }
    }

    func requestSceneProbe(siteID: UUID?) {
        guard enabled(\.allowSceneRequests) else {
            record(.scene, "Scene request blocked: enable Shell Lab and scene requests first")
            return
        }
        let activity: NSUserActivity?
        if options.sceneRequestWithUserActivity {
            let probe = NSUserActivity(activityType: "com.beryllium.shelllab.scene-probe")
            if let siteID { probe.userInfo = ["siteID": siteID.uuidString] }
            activity = probe
        } else {
            activity = nil
        }
        record(.scene, "Requested an additional scene; the OS may refuse or reuse one")
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { [weak self] error in
            Task { @MainActor in self?.record(.scene, "Activation error: \(error.localizedDescription)") }
        }
    }

    func prepareReport() throws -> URL {
        captureSceneSnapshot()
        var lines = ["Beryllium Shell Laboratory — diagnostic report",
                     "Created: \(Date().formatted(date: .abbreviated, time: .standard))",
                     "iOS: \(UIDevice.current.systemVersion)",
                     "Device: \(UIDevice.current.model)",
                     "Note: scene counts do NOT prove separate App Switcher cards.", "", "Settings:"]
        let json = try JSONEncoder().encode(options)
        lines.append(String(data: json, encoding: .utf8) ?? "Unavailable")
        lines.append("\nEvents (latest \(entries.count)):")
        for item in entries {
            lines.append("\(item.date.formatted(date: .numeric, time: .standard)) [\(item.category.rawValue)] \(item.message)")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Beryllium-ShellLab-Report.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func persistOptions() {
        if let bytes = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(bytes, forKey: Self.optionsKey)
        }
    }
    private func persistEntries() {
        if let bytes = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(bytes, forKey: Self.logsKey)
        }
    }
}
