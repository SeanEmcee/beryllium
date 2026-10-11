// Deep-link mailbox for iOS Shortcuts / Home Screen app launch.
// One full-screen presenter (ContentView) handles both taps and incoming URLs.
// The URL can arrive before the window is active during a cold start.

import SwiftUI

@MainActor
final class BerylliumLaunchRouter: ObservableObject {
    @Published private(set) var pendingSiteID: UUID?

    func receive(_ url: URL) {
        guard url.scheme?.lowercased() == "beryllium",
              url.host?.lowercased() == "open",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let string = parts.queryItems?.first(where: { $0.name == "id" })?.value,
              let identifier = UUID(uuidString: string) else {
            // Ignore unrelated or malformed URLs; never present an invalid site.
            return
        }
        requestSite(identifier)
    }

    func requestSite(_ identifier: UUID) {
        let lab = BerylliumShellLab.shared
        if lab.enabled(\.deduplicateShortcutLaunch), pendingSiteID == identifier {
            lab.record(.launch, "Ignored duplicate link for \(identifier.uuidString)")
            return
        }
        lab.record(.launch, "Queued launch for \(identifier.uuidString)")
        pendingSiteID = identifier
    }

    func consume(_ identifier: UUID) {
        if pendingSiteID == identifier { pendingSiteID = nil }
    }
}
