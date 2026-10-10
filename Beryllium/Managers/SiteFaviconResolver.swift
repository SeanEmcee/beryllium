import Foundation
import ImageIO
import UIKit
import WebKit

// Resolves the page-declared browser TAB icon first, then its iOS touch icon.
// Unlike guessed /apple-touch-icon.png URLs, <link rel="icon"> URLs are
// resolved against the response URL / HTML <base> element.
enum SiteFaviconResolver {
    private struct Candidate {
        let url: URL
        let rank: Int
    }

    static func fetch(for siteURL: URL) async throws -> Data {
        guard ["https", "http"].contains(siteURL.scheme?.lowercased() ?? "") else {
            throw URLError(.unsupportedURL)
        }
        var request = URLRequest(url: siteURL)
        request.timeoutInterval = 12
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (body, response) = try await URLSession.shared.data(for: request)
        guard body.count < 3_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        let html = String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        let finalURL = response.url ?? siteURL
        let baseTag = firstTag("base", in: html)
        let baseHref = baseTag.flatMap { attributes(in: $0)["href"] }
        let baseURL = baseHref.flatMap { URL(string: $0, relativeTo: finalURL)?.absoluteURL } ?? finalURL
        var candidates = [Candidate]()
        for link in tags("link", in: html) {
            let values = attributes(in: link)
            guard let href = values["href"], !href.isEmpty,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  ["https", "http", "data"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let rel = Set((values["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            let type = (values["type"] ?? "").lowercased()
            let sizes = values["sizes"] ?? ""
            if rel.contains("icon") { // Browser-tab favicon takes priority.
                let sizeScore = sizes.contains("48") || sizes.contains("32") ? 12 : 0
                let typeScore = type.contains("svg") || href.lowercased().contains(".svg") ? 8 : 0
                candidates.append(Candidate(url: url, rank: 100 + sizeScore + typeScore))
            } else if rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed") {
                candidates.append(Candidate(url: url, rank: 40))
            }
        }
        if let origin = URL(string: "/favicon.ico", relativeTo: finalURL)?.absoluteURL {
            candidates.append(Candidate(url: origin, rank: 30))
        }
        if let origin = URL(string: "/apple-touch-icon.png", relativeTo: finalURL)?.absoluteURL {
            candidates.append(Candidate(url: origin, rank: 20))
        }
        let sorted = candidates.enumerated().sorted {
            if $0.element.rank == $1.element.rank { return $0.offset > $1.offset }
            return $0.element.rank > $1.element.rank
        }
        var checked = Set<URL>()
        for entry in sorted {
            let iconURL = entry.element.url
            guard checked.insert(iconURL).inserted else { continue }
            do {
                let bytes: Data
                if iconURL.scheme?.lowercased() == "data" {
                    let components = iconURL.absoluteString.split(separator: ",", maxSplits: 1)
                    guard components.count == 2 else { continue }
                    if components[0].contains(";base64") {
                        guard let decoded = Data(base64Encoded: String(components[1])) else { continue }
                        bytes = decoded
                    } else {
                        bytes = Data((String(components[1]).removingPercentEncoding ?? "").utf8)
                    }
                } else {
                    var iconRequest = URLRequest(url: iconURL)
                    iconRequest.timeoutInterval = 8
                    let (download, result) = try await URLSession.shared.data(for: iconRequest)
                    guard (result as? HTTPURLResponse)?.statusCode == 200 else { continue }
                    bytes = download
                }
                guard !bytes.isEmpty, bytes.count < 2_000_000 else { continue }
                if let picture = UIImage(data: bytes), let png = picture.pngData() { return png }
                if let imageSource = CGImageSourceCreateWithData(bytes as CFData, nil),
                   let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                    if let png = UIImage(cgImage: image).pngData() { return png }
                }
                if iconURL.pathExtension.lowercased() == "svg" ||
                   iconURL.absoluteString.contains("image/svg+xml") ||
                   String(data: bytes.prefix(1024), encoding: .utf8)?.contains("<svg") == true {
                    // iOS UIImage doesn't decode SVG directly; rasterize it
                    // in an isolated temporary WKWebView to keep tab-icon parity.
                    if let png = await SVGIconSnapshotter().render(data: bytes) { return png }
                }
            } catch { continue }
        }
        throw URLError(.fileDoesNotExist)
    }

    private static func tags(_ name: String, in text: String) -> [String] {
        guard let exp = try? NSRegularExpression(pattern: "<" + name + "\\b[^>]*>", options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        return exp.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func firstTag(_ name: String, in text: String) -> String? {
        tags(name, in: text).first
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let exp = try? NSRegularExpression(
            pattern: "([\\w:-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
            options: .caseInsensitive
        ) else { return [:] }
        let ns = tag as NSString
        var result: [String: String] = [:]
        for match in exp.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            guard match.range(at: 1).location != NSNotFound else { continue }
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            if let part = [2, 3, 4].first(where: { match.range(at: $0).location != NSNotFound }) {
                result[key] = ns.substring(with: match.range(at: part))
            }
        }
        return result
    }
}

// Owned only for the duration of an SVG rasterization. It cannot access the
// site's cookies, logged-in pages or Beryllium's active web view.
@MainActor private final class SVGIconSnapshotter: NSObject, WKNavigationDelegate {
    private var view: WKWebView?
    private var continuation: CheckedContinuation<Data?, Never>?

    func render(data: Data) async -> Data? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 180, height: 180))
            view.isOpaque = false
            view.backgroundColor = .clear
            view.scrollView.isScrollEnabled = false
            view.navigationDelegate = self
            self.view = view
            // Never let a malformed SVG leave icon fetching waiting forever.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.finish(nil)
            }
            let b64 = data.base64EncodedString()
            view.loadHTMLString("""
                <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
                <body style="margin:0;background:transparent;display:grid;place-items:center;width:180px;height:180px;overflow:hidden">
                <img width="170" height="170" src="data:image/svg+xml;base64,\(b64)" style="object-fit:contain" />
                </body></html>
                """, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 180, height: 180)
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            self?.finish(image?.pngData())
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }
    private func finish(_ data: Data?) {
        guard let continuation else { return }
        self.continuation = nil
        view?.navigationDelegate = nil
        view = nil
        continuation.resume(returning: data)
    }
}
