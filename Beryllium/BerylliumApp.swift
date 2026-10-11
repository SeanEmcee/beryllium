// beryllium - turn websites into apps on your homescreen
// main app entry point

import SwiftUI

@main
struct BerylliumApp: App {
    @StateObject private var siteStore = SiteStore()
    @StateObject private var appearance = BerylliumAppearance()
    @StateObject private var shellLab = BerylliumShellLab.shared

    var body: some Scene {
        WindowGroup {
            BerylliumSceneRoot()
                .environmentObject(siteStore)
                .environmentObject(appearance)
                .environmentObject(shellLab)
                .preferredColorScheme(appearance.preferredScheme)
                .statusBarHidden(false)
        }
    }
}


// Every WindowGroup instance owns its own launch router. This is essential
// for the experiment: additional scenes must not all present the same site.
private struct BerylliumSceneRoot: View {
    @StateObject private var router = BerylliumLaunchRouter()
    @EnvironmentObject private var lab: BerylliumShellLab

    var body: some View {
        ContentView()
            .environmentObject(router)
            .onOpenURL { url in router.receive(url) }
            .onContinueUserActivity("com.beryllium.shelllab.scene-probe") { activity in
                if let raw = activity.userInfo?["siteID"] as? String,
                   let siteID = UUID(uuidString: raw) {
                    lab.record(.scene, "New scene received requested site \(siteID.uuidString)")
                    router.requestSite(siteID)
                } else {
                    lab.record(.scene, "Scene probe activity arrived without a website ID")
                }
            }
            .onAppear { lab.record(.scene, "Scene root appeared") }
    }
}
