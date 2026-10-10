// web container view - hosts a wkwebview that wraps the configured website
// this is the core of beryllium: a native container instead of opening safari

import SwiftUI
import WebKit

struct WebContainerView: View {
    let site: WebSite
    @Environment(\.dismiss) private var dismiss
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = true
    @State private var currentURL: String = ""
    @State private var showingEditSheet = false
    @State private var showControls = false
    @State private var showingShareSheet = false
    @State private var showingExtensions = false
    @ObservedObject private var extensionRuntime: ExtensionRuntime
    private let warmSession: WarmWebSession

    init(site: WebSite) {
        self.site = site
        let session = WarmWebSessionPool.shared.session(for: site)
        warmSession = session
        _extensionRuntime = ObservedObject(wrappedValue: session.extensions)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // the webview fills the entire screen
            Group {
                if extensionRuntime.isPrepared {
                    WebView(
                        site: site,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        isLoading: $isLoading,
                        currentURL: $currentURL,
                        extensionController: extensionRuntime.controller,
                        warmSession: warmSession
                    )
                } else {
                    ProgressView("Preparing extensions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(site.enableFullScreen ? .all : .init(), edges: .vertical)

            // A thin dock with a material background extending all the way
            // to the device bottom. Only shown if enabled for this shortcut.
            if showControls {
                HStack(spacing: 0) {
                    dockButton("xmark", label: "Close") { dismiss() }
                    Spacer(minLength: 2)
                    dockButton("chevron.left", label: "Back", disabled: !canGoBack) {
                        NotificationCenter.default.post(name: .webViewGoBack, object: nil)
                    }
                    dockButton("chevron.right", label: "Forward", disabled: !canGoForward) {
                        NotificationCenter.default.post(name: .webViewGoForward, object: nil)
                    }
                    dockButton(isLoading ? "xmark" : "arrow.clockwise", label: "Reload") {
                        NotificationCenter.default.post(name: .webViewReload, object: nil)
                    }
                    if extensionRuntime.enabledCount > 0 {
                        dockButton("puzzlepiece.extension", label: "Extensions") { showingExtensions = true }
                    }
                    dockButton("square.and.arrow.up", label: "Share") { showingShareSheet = true }
                    dockButton("gearshape", label: "Settings") { showingEditSheet = true }
                }
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    Rectangle().fill(.ultraThinMaterial)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // The extension launcher is anchored to the actual browser,
            // not injected into page HTML. It remains usable in fullscreen.
            if extensionRuntime.enabledCount > 0 && !showControls {
                Button { showingExtensions = true } label: {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(13)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Extensions")
                .padding(.bottom, 10)
            }
        }
        .task(id: site.id) {
            // A warm session must not unload or recreate extension contexts.
            if !extensionRuntime.isPrepared {
                await extensionRuntime.prepare(siteID: site.id)
            }
        }
        .sheet(isPresented: $showingExtensions) {
            ExtensionMenuView(runtime: extensionRuntime)
        }
        .onAppear { showControls = site.navigationDockEnabled }
        .statusBarHidden(site.enableFullScreen)
        .onTapGesture(count: 3) {
            // triple tap toggles the control bar visibility
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls.toggle()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            SiteEditorView(mode: .edit(site))
        }
        .sheet(isPresented: $showingShareSheet) {
            AddToHomeScreenView(site: site)
        }
        .modifier(OrientationLockModifier(lock: site.orientationLock))
    }

    private func dockButton(_ symbol: String, label: String,
                            disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}

// guided view for adding a home screen shortcut
// starts a local http server and opens safari to the instruction page
struct AddToHomeScreenView: View {
    let site: WebSite
    @Environment(\.dismiss) private var dismiss
    @State private var server = LocalServer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                SiteIconView(site: site, size: 80)

                Text(site.name)
                    .font(.title2.bold())

                Text("add a home screen shortcut that opens this site directly in beryllium")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    openInSafari()
                } label: {
                    Label("add to home screen", systemImage: "plus.app")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)

                Text("opens safari — follow the steps to add a shortcut")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .navigationTitle("home screen shortcut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
        .onDisappear {
            server.stop()
        }
    }

    private func openInSafari() {
        let html = ShortcutManager.generateShortcutHTML(for: site)
        server.start(html: html) { port in
            guard let port = port else { return }
            if let url = URL(string: "http://localhost:\(port)") {
                UIApplication.shared.open(url)
            }
        }
    }
}

// notification names for controlling the webview from swiftui buttons
extension Notification.Name {
    static let webViewGoBack = Notification.Name("webViewGoBack")
    static let webViewGoForward = Notification.Name("webViewGoForward")
    static let webViewReload = Notification.Name("webViewReload")
}

// uiviewrepresentable wrapper around wkwebview
struct WebView: UIViewRepresentable {
    let site: WebSite
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var currentURL: String
    let extensionController: WKWebExtensionController?
    let warmSession: WarmWebSession

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        if let reused = warmSession.webView {
            // Coordinators are view lifetimes; WKWebView is a session lifetime.
            // Always wire the NEW coordinator to the reused WebView.
            reused.navigationDelegate = context.coordinator
            reused.scrollView.contentInsetAdjustmentBehavior = .never
            reused.scrollView.contentInset = .zero
            reused.scrollView.scrollIndicatorInsets = .zero
            context.coordinator.observe(reused)
            context.coordinator.subscribeToControls(reused)
            DispatchQueue.main.async {
                canGoBack = reused.canGoBack
                canGoForward = reused.canGoForward
                isLoading = reused.isLoading
                currentURL = reused.url?.absoluteString ?? ""
            }
            return reused
        }
        let config = WKWebViewConfiguration()
        // A controller must be attached before constructing WKWebView.
        config.webExtensionController = extensionController

        // configure javascript preference
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = site.enableJavaScript
        config.defaultWebpagePreferences = prefs

        // allow inline media playback (important for video-heavy sites)
        config.allowsInlineMediaPlayback = site.allowInlineMedia
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero

        // set custom user agent if configured
        if !site.userAgent.isEmpty {
            webView.customUserAgent = site.userAgent
        }

        // observe navigation state changes
        context.coordinator.observe(webView)

        // subscribe to navigation control notifications
        context.coordinator.subscribeToControls(webView)

        // Save BEFORE navigating so a subsequent launch can reuse this view.
        warmSession.webView = webView

        // Load exactly once per warm session; returning to an open website
        // preserves its actual page, not merely a screenshot or HTTP cache.
        if let url = site.url {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // no dynamic updates needed; the webview manages its own state
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        private var observations: [NSKeyValueObservation] = []
        private var notificationTokens: [Any] = []

        init(_ parent: WebView) {
            self.parent = parent
        }

        deinit {
            observations.removeAll()
            notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        }

        // kvo on webview properties to update swiftui state
        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.canGoBack) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.parent.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.parent.canGoForward = wv.canGoForward }
                },
                webView.observe(\.isLoading) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.parent.isLoading = wv.isLoading }
                },
                webView.observe(\.url) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.parent.currentURL = wv.url?.absoluteString ?? "" }
                }
            ]
        }

        // listen for navigation button taps sent via notificationcenter
        func subscribeToControls(_ webView: WKWebView) {
            notificationTokens = [
                NotificationCenter.default.addObserver(
                    forName: .webViewGoBack, object: nil, queue: .main
                ) { _ in webView.goBack() },
                NotificationCenter.default.addObserver(
                    forName: .webViewGoForward, object: nil, queue: .main
                ) { _ in webView.goForward() },
                NotificationCenter.default.addObserver(
                    forName: .webViewReload, object: nil, queue: .main
                ) { _ in
                    if webView.isLoading { webView.stopLoading() }
                    else { webView.reload() }
                }
            ]
        }

        // handle stikjit url scheme if enabled
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url,
               parent.site.enableStikJIT,
               url.scheme == "stikjit" {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }
    }
}
