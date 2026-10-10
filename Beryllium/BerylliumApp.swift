// beryllium - turn websites into apps on your homescreen
// main app entry point

import SwiftUI

@main
struct BerylliumApp: App {
    @StateObject private var siteStore = SiteStore()
    @StateObject private var appearance = BerylliumAppearance()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(siteStore)
                .environmentObject(appearance)
                .handleBerylliumURLs()
                .preferredColorScheme(appearance.preferredScheme)
        }
    }
}
