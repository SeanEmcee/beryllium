import SwiftUI
import UIKit

enum BerylliumAppearanceMode: String, CaseIterable, Identifiable {
    case dark = "Dark", light = "Light", system = "System"
    var id: String { rawValue }
}

enum BerylliumTextMode: String, CaseIterable, Identifiable, Codable {
    case automatic = "System Text", solid = "Solid Color", gradient = "Gradient"
    var id: String { rawValue }
}

enum TypographyArea: String, CaseIterable, Identifiable, Codable {
    case wordmark = "Beryllium Wordmark"
    case siteName = "Website Names"
    case siteURL = "Website Addresses"
    case emptyTitle = "Empty State Heading"
    case emptyDetail = "Empty State Details"
    case managerTitle = "App Manager Title"
    var id: String { rawValue }
    var example: String {
        switch self {
        case .wordmark: return "Beryllium"
        case .siteName: return "Monochrome"
        case .siteURL: return "https://monochrome.st"
        case .emptyTitle: return "No websites yet"
        case .emptyDetail: return "Add your first application"
        case .managerTitle: return "Monochrome"
        }
    }
    var defaultSize: Double {
        switch self {
        case .wordmark: return 20
        case .siteName, .emptyTitle, .managerTitle: return 18
        case .siteURL, .emptyDetail: return 13
        }
    }
}

enum TextShaderEffect: String, CaseIterable, Identifiable, Codable {
    case none = "None", shimmer = "Shimmer", aurora = "Aurora", pulse = "Pulse", holographic = "Holographic"
    var id: String { rawValue }
    var number: Float {
        switch self {
        case .none: return 0
        case .shimmer: return 1
        case .aurora: return 2
        case .pulse: return 3
        case .holographic: return 4
        }
    }
}

struct TextGradientStop: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var hex: String
    var position: Double
}

struct TypographyStyle: Codable, Equatable {
    var mode: BerylliumTextMode = .automatic
    var stops: [TextGradientStop] = [
        TextGradientStop(hex: "D6F4FF", position: 0),
        TextGradientStop(hex: "6D83FF", position: 1)
    ]
    var angle: Double = 0
    var fontSize: Double = 18
    var heavy: Bool = true
    var outlineWidth: Double = 0
    var outlineHex: String = "111827"
    var shader: TextShaderEffect = .none
    var shaderStrength: Double = 0.5
    var shaderSpeed: Double = 1
    // When selectionLength > 0, effects apply only to this character range.
    // Other characters use an accessible system-text fallback.
    var selectionStart: Int = 0
    var selectionLength: Int = 0

    static func initial(for area: TypographyArea) -> TypographyStyle {
        var style = TypographyStyle()
        style.fontSize = area.defaultSize
        return style
    }

    func fillStyle(for scheme: ColorScheme, wordmark: Bool = false) -> AnyShapeStyle {
        switch mode {
        case .automatic:
            if wordmark {
                let base: Color = scheme == .dark ? .white : .black
                return AnyShapeStyle(LinearGradient(colors: [base, base.opacity(0.88), .cyan], startPoint: .leading, endPoint: .trailing))
            }
            return AnyShapeStyle(Color.primary)
        case .solid:
            return AnyShapeStyle(Color(hex: stops.first?.hex ?? "FFFFFF") ?? .white)
        case .gradient:
            let sorted = stops.sorted { $0.position < $1.position }
            let gradientStops = sorted.map {
                Gradient.Stop(color: Color(hex: $0.hex) ?? .white, location: CGFloat($0.position))
            }
            let radians = angle * .pi / 180
            let dx = cos(radians) * 0.5
            let dy = sin(radians) * 0.5
            return AnyShapeStyle(LinearGradient(
                stops: gradientStops,
                startPoint: UnitPoint(x: CGFloat(0.5 - dx), y: CGFloat(0.5 - dy)),
                endPoint: UnitPoint(x: CGFloat(0.5 + dx), y: CGFloat(0.5 + dy))
            ))
        }
    }
}

/// Controls only Beryllium's native SwiftUI text, never a loaded site's DOM/CSS.
final class BerylliumAppearance: ObservableObject {
    private static let modeKey = "Beryllium.appearance.mode"
    private static let stylesKey = "Beryllium.typography.v4"
    @Published var mode: BerylliumAppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    @Published private(set) var styles: [String: TypographyStyle] {
        didSet {
            if let data = try? JSONEncoder().encode(styles) {
                UserDefaults.standard.set(data, forKey: Self.stylesKey)
            }
        }
    }
    init() {
        let defaults = UserDefaults.standard
        mode = BerylliumAppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "Dark") ?? .dark
        styles = (defaults.data(forKey: Self.stylesKey)
                  .flatMap { try? JSONDecoder().decode([String: TypographyStyle].self, from: $0) }) ?? [:]
        // Migrate users of the earlier two-color typography customization.
        if defaults.data(forKey: Self.stylesKey) == nil,
           let oldMode = defaults.string(forKey: "Beryllium.appearance.text"),
           let textMode = BerylliumTextMode(rawValue: oldMode) {
            for area in TypographyArea.allCases {
                var style = TypographyStyle.initial(for: area)
                style.mode = textMode
                style.stops = [
                    TextGradientStop(hex: defaults.string(forKey: "Beryllium.appearance.firstHex") ?? "D6F4FF", position: 0),
                    TextGradientStop(hex: defaults.string(forKey: "Beryllium.appearance.secondHex") ?? "6D83FF", position: 1)
                ]
                styles[area.rawValue] = style
            }
        }
    }
    var preferredScheme: ColorScheme? {
        switch mode { case .dark: return .dark; case .light: return .light; case .system: return nil }
    }
    func style(for area: TypographyArea) -> TypographyStyle {
        styles[area.rawValue] ?? .initial(for: area)
    }
    func save(_ style: TypographyStyle, for area: TypographyArea) {
        styles[area.rawValue] = style
    }
    func reset(_ area: TypographyArea) {
        styles[area.rawValue] = .initial(for: area)
    }
}

extension Color {
    var berylliumRGBHex: String {
        let native = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "FFFFFF" }
        return String(format: "%02X%02X%02X", Int((min(max(r, 0), 1) * 255).rounded()),
                      Int((min(max(g, 0), 1) * 255).rounded()), Int((min(max(b, 0), 1) * 255).rounded()))
    }
}
