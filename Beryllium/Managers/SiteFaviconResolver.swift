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

    // Prefer actual Home Screen artwork (>=180px), manifest icons and scalable
    // SVGs. A browser-tab 16px icon is only the final fallback.
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
        var candidates: [Candidate] = []
        var manifestURL: URL?
        for link in tags("link", in: html) {
            let values = attributes(in: link)
            guard let href = values["href"], !href.isEmpty,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  ["https", "http", "data"].contains(url.scheme?.lowercased() ?? "") else { continue }
            let rel = Set((values["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            let size = declaredPixels(values["sizes"] ?? "")
            let svg = (values["type"] ?? "").contains("svg") || url.pathExtension.lowercased() == "svg"
            if rel.contains("manifest"), url.scheme != "data" { manifestURL = url }
            if rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed") {
                candidates.append(Candidate(url: url, rank: 250 + min(size, 512)))
            } else if rel.contains("icon") {
                candidates.append(Candidate(url: url, rank: (svg ? 720 : 50) + min(size, 512)))
            }
        }
        if let manifestURL, let icons = await manifestCandidates(at: manifestURL) {
            candidates.append(contentsOf: icons)
        }
        if let origin = URL(string: "/apple-touch-icon.png", relativeTo: finalURL)?.absoluteURL {
            candidates.append(Candidate(url: origin, rank: 420))
        }
        if let origin = URL(string: "/favicon.ico", relativeTo: finalURL)?.absoluteURL {
            candidates.append(Candidate(url: origin, rank: 10))
        }
        let sorted = candidates.sorted { $0.rank > $1.rank }
        var checked = Set<URL>()
        var best: Data?
        var bestScore = -1
        // Stop at 12 distinct candidates, avoiding unbounded network traffic.
        for entry in sorted {
            let url = entry.url
            guard checked.count < 12, checked.insert(url).inserted else { continue }
            do {
                let bytes: Data
                if url.scheme?.lowercased() == "data" {
                    let parts = url.absoluteString.split(separator: ",", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    bytes = parts[0].contains(";base64")
                        ? (Data(base64Encoded: String(parts[1])) ?? Data())
                        : Data((String(parts[1]).removingPercentEncoding ?? "").utf8)
                } else {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 8
                    let (download, response) = try await URLSession.shared.data(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                    bytes = download
                }
                guard !bytes.isEmpty, bytes.count < 4_000_000 else { continue }
                let svg = url.pathExtension.lowercased() == "svg" ||
                    url.absoluteString.contains("image/svg+xml") ||
                    (String(data: bytes.prefix(1024), encoding: .utf8)?.contains("<svg") == true)
                if svg, let png = await SVGIconSnapshotter().render(data: bytes) {
                    let score = entry.rank + 800
                    if score > bestScore { bestScore = score; best = png }
                    continue
                }
                guard let image = UIImage(data: bytes) ?? cgImage(from: bytes),
                      let png = image.pngData() else { continue }
                let pixelSize = min(image.size.width * image.scale, image.size.height * image.scale)
                let score = Int(min(pixelSize, 1024)) * 2 + min(entry.rank, 400)
                if score > bestScore { bestScore = score; best = png }
                if pixelSize >= 512 && entry.rank >= 300 { return png }
            } catch { continue }
        }
        if let best { return best }
        throw URLError(.fileDoesNotExist)
    }

    private static func declaredPixels(_ sizes: String) -> Int {
        if sizes.lowercased().contains("any") { return 600 }
        let values = sizes.split(whereSeparator: \.isWhitespace).compactMap { chunk -> Int? in
            let parts = chunk.lowercased().split(separator: "x")
            guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
            return min(w, h)
        }
        return values.max() ?? 0
    }

    private static func cgImage(from bytes: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func manifestCandidates(at url: URL) async -> [Candidate]? {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 7
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count < 250_000,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let icons = object["icons"] as? [[String: Any]] else { return nil }
            return icons.compactMap { entry -> Candidate? in
                guard let src = entry["src"] as? String,
                      let iconURL = URL(string: src, relativeTo: url)?.absoluteURL,
                      ["https", "http"].contains(iconURL.scheme?.lowercased() ?? "") else { return nil }
                let size = declaredPixels(entry["sizes"] as? String ?? "")
                let isSVG = (entry["type"] as? String ?? "").contains("svg")
                return Candidate(url: iconURL, rank: (isSVG ? 740 : 300) + min(size, 512))
            }
        } catch { return nil }
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
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 512, height: 512))
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
                <body style="margin:0;background:transparent;display:grid;place-items:center;width:512px;height:512px;overflow:hidden">
                <img width="512" height="512" src="data:image/svg+xml;base64,\(b64)" style="object-fit:contain" />
                </body></html>
                """, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 512, height: 512)
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
