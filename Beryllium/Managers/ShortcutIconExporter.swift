import SwiftUI
import UIKit

/// Produces a full-resolution PNG asset for the user to select in Shortcuts.
/// iOS does not permit apps to silently create independent Home Screen icons.
enum ShortcutIconExporter {
    @MainActor
    static func prepare(for site: WebSite) async -> URL? {
        let resolvedBytes = site.url.flatMap { url in url.scheme == "https" ? url : nil }
        let downloaded = await resolveIcon(resolvedBytes)
        let baseImage = downloaded.flatMap(UIImage.init(data:)) ?? site.iconSource.uiImage
        let size = CGSize(width: 1024, height: 1024)
        let color = UIColor(Color(hex: site.iconColorHex) ?? .black)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            color.setFill()
            context.fill(bounds)
            if let image = baseImage, image.size.width > 0, image.size.height > 0 {
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (size.width - target.width) / 2,
                                      y: (size.height - target.height) / 2,
                                      width: target.width, height: target.height))
            } else {
                let label = String(site.name.prefix(1)).uppercased() as NSString
                let font = UIFont.systemFont(ofSize: 540, weight: .bold)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let dimensions = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: (1024 - dimensions.width) / 2,
                                       y: (1024 - dimensions.height) / 2 - 38),
                           withAttributes: attributes)
            }
        }
        guard let bytes = result.pngData() else { return nil }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("Beryllium-\(site.id.uuidString)-icon.png")
        do { try bytes.write(to: target, options: .atomic); return target }
        catch { return nil }
    }

    private static func resolveIcon(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        return try? await SiteFaviconResolver.fetch(for: url)
    }
}
