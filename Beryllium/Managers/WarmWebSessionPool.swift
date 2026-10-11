import Foundation
import WebKit

/// Keeps up to two existing browser sessions warm, so re-opening a shortcut
/// does not always discard its DOM, scroll position, media state and history.
/// Requires the Beryllium Extension Manager overlay (ExtensionRuntime/Library).
/// Beryllium remains a normal WKWebView host. This does NOT enable native JIT,
/// bypass WebKit, keep apps running indefinitely, or guarantee any frame rate.
@MainActor
final class WarmWebSession {
    let siteID: UUID
    let configurationSignature: String
    let extensions = ExtensionRuntime()
    var webView: WKWebView?

    init(siteID: UUID, configurationSignature: String) {
        self.siteID = siteID
        self.configurationSignature = configurationSignature
    }
}

@MainActor
final class WarmWebSessionPool {
    static let shared = WarmWebSessionPool()

    private var sessions: [UUID: WarmWebSession] = [:]
    private var recent: [UUID] = []
    private var maximumWarmSessions: Int {
        let lab = BerylliumShellLab.shared.options
        return lab.enabled && lab.warmSessionsEnabled ? lab.warmSessionLimit : 2
    }

    private init() { }

    func session(for site: WebSite) -> WarmWebSession {
        let labOptions = BerylliumShellLab.shared.options
        let extensionIDs = (labOptions.enabled && !labOptions.extensionsEnabled ? [] : ExtensionLibrary.shared.enabledExtensions(siteID: site.id))
            .map { "\($0.id.uuidString):\($0.version)" }
            .sorted().joined(separator: ",")
        // A modified site configuration or different extension set must never
        // reuse an existing WKWebView with the old native configuration.
        let signature = [
            site.urlString,
            site.enableJavaScript.description,
            site.allowInlineMedia.description,
            site.userAgent,
            extensionIDs,
            labOptions.enabled.description,
            labOptions.ephemeralSiteIsolation.description,
            labOptions.suppressJavaScript.description,
            labOptions.suppressInlineVideo.description,
            labOptions.suppressSwipeNavigation.description,
            labOptions.extensionsEnabled.description
        ].joined(separator: "\u{001F}")

        if labOptions.enabled && !labOptions.warmSessionsEnabled {
            recordSessionEvent("Created uncached session for site \(site.id.uuidString)")
            return WarmWebSession(siteID: site.id, configurationSignature: signature)
        }
        if let existing = sessions[site.id], existing.configurationSignature == signature {
            markRecent(site.id)
            // Important: this method is called while SwiftUI constructs a view.
            // Re-logging a cache hit publishes another view update in a loop.
            return existing
        }

        let fresh = WarmWebSession(siteID: site.id, configurationSignature: signature)
        sessions[site.id] = fresh
        markRecent(site.id)
        recordSessionEvent("Created new warm session for site \(site.id.uuidString)")
        return fresh
    }

    // Never synchronously publish Shell Lab logs from session(for:).
    // WebContainerView calls session(for:) during SwiftUI view construction.
    // Only real session creation/eviction gets a deferred diagnostic entry.
    private func recordSessionEvent(_ message: String) {
        Task { @MainActor in
            BerylliumShellLab.shared.record(.session, message)
        }
    }

    private func markRecent(_ siteID: UUID) {
        recent.removeAll { $0 == siteID }
        recent.append(siteID)
        while recent.count > maximumWarmSessions {
            let expired = recent.removeFirst()
            sessions.removeValue(forKey: expired)
            recordSessionEvent("Evicted warm session for site \(expired.uuidString)")
        }
    }

    /// Explicitly release warmed sessions if a settings screen offers a reset.
    func clear() {
        sessions.removeAll()
        recent.removeAll()
        BerylliumShellLab.shared.record(.session, "All warm sessions discarded")
    }
}
