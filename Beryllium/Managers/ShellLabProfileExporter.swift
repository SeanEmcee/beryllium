import Foundation
import SwiftUI
import UIKit

// TEST ONLY: A user-installed Web Clip profile is not an independently signed
// iOS application. iOS may reject custom URL schemes in Web Clip payloads.
@MainActor
enum ShellLabProfileExporter {
    static func make(for site: WebSite, options: ShellLabOptions) throws -> URL {
        let payloadID = "com.beryllium.shelllab.webclip.\(site.id.uuidString.lowercased())"
        let destination = options.profileDestination == .deepLink
            ? "beryllium://open?id=\(site.id.uuidString)" : site.urlString
        var clip: [String: Any] = [
            "PayloadType": "com.apple.webClip.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": payloadID,
            "PayloadUUID": UUID().uuidString,
            "Label": site.name,
            "URL": destination,
            "IsRemovable": true,
            "FullScreen": options.profileFullScreen,
            "Precomposed": true
        ]
        if options.profileIncludeIcon {
            let image = site.iconSource.uiImage ?? fallbackIcon(for: site)
            // Apple's WebClip payload recommends <= 400 x 400 PNG under 1 MB.
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180))
            let normalized = renderer.pngData { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 180, height: 180))
            }
            if normalized.count < 1_000_000 { clip["Icon"] = normalized }
        }
        let root: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "com.beryllium.shelllab.profile.\(site.id.uuidString.lowercased())",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Beryllium Test — \(site.name)",
            "PayloadOrganization": "Beryllium Shell Laboratory",
            "PayloadDescription": "Experimental removable Home Screen Web Clip. Does not install another app.",
            "PayloadContent": [clip]
        ]
        let bytes = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Beryllium-ShellLab-\(site.id.uuidString).mobileconfig")
        try bytes.write(to: file, options: .atomic)
        return file
    }

    private static func fallbackIcon(for site: WebSite) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: 180, height: 180)
        return UIGraphicsImageRenderer(size: bounds.size).image { context in
            let fill = UIColor(Color(hex: site.iconColorHex) ?? .blue)
            fill.setFill()
            context.fill(bounds)
            let letter = String(site.name.prefix(1)).uppercased() as NSString
            let font = UIFont.systemFont(ofSize: 90, weight: .bold)
            let size = letter.size(withAttributes: [.font: font])
            letter.draw(at: CGPoint(x: (180 - size.width) / 2, y: (180 - size.height) / 2),
                        withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
    }
}
