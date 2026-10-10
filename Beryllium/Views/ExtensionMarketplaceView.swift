import SwiftUI
import UIKit
import WebKit

// Search interface, not a claim that Chrome's "Add to Chrome" button works
// in WKWebView or that another app's Safari Extension can be copied here.
struct ExtensionMarketplaceView: View {
    let kind: ExtensionKind
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var displayedURL: URL?

    private var searchURL: URL {
        if kind == .chromium {
            let term = search.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            return URL(string: "https://chromewebstore.google.com/search/\(term)")!
        }
        var url = URLComponents(string: "https://apps.apple.com/us/search")!
        url.queryItems = [URLQueryItem(name: "term", value: search.isEmpty ? "Safari extensions" : search + " Safari extension")]
        return url.url!
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Search extensions", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(runSearch)
                    Button("Search", action: runSearch).buttonStyle(.borderedProminent)
                }
                .padding(12)
                Text(kind == .chromium
                     ? "Browse Chrome Web Store listings. 'Add to Chrome' cannot install directly into Beryllium. For supported packages, use Install from ZIP URL or Import ZIP in the app manager."
                     : "Safari extensions distributed inside other iOS apps cannot be imported from the App Store. The Safari-compatible ZIP importer supports portable WebExtensions only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                MarketplaceWebView(url: displayedURL ?? searchURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(kind == .chromium ? "Chrome Web Store" : "Safari Extensions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        UIApplication.shared.open(displayedURL ?? searchURL)
                    } label: { Label("Open in Browser", systemImage: "arrow.up.right.square") }
                }
            }
        }
    }
    private func runSearch() { displayedURL = searchURL }
}

private struct MarketplaceWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url?.absoluteString != url.absoluteString {
            view.load(URLRequest(url: url))
        }
    }
}
