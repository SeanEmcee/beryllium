import SwiftUI
import UIKit

enum BerylliumAppearanceMode: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case system = "System"

    var id: String { rawValue }
}

enum BerylliumTextMode: String, CaseIterable, Identifiable {
    case automatic = "System Text"
    case solid = "Solid Color"
    case gradient = "Gradient"

    var id: String { rawValue }
}

/// Appearance applies to Beryllium's native dashboard and controls,
/// not the contents of loaded third-party websites.
final class BerylliumAppearance: ObservableObject {
    private static let modeKey = "Beryllium.appearance.mode"
    private static let textKey = "Beryllium.appearance.text"
    private static let firstKey = "Beryllium.appearance.firstHex"
    private static let secondKey = "Beryllium.appearance.secondHex"

    @Published var mode: BerylliumAppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    @Published var textMode: BerylliumTextMode {
        didSet { UserDefaults.standard.set(textMode.rawValue, forKey: Self.textKey) }
    }
    @Published var firstHex: String {
        didSet { UserDefaults.standard.set(firstHex, forKey: Self.firstKey) }
    }
    @Published var secondHex: String {
        didSet { UserDefaults.standard.set(secondHex, forKey: Self.secondKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        mode = BerylliumAppearanceMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "Dark") ?? .dark
        textMode = BerylliumTextMode(rawValue: defaults.string(forKey: Self.textKey) ?? "System Text") ?? .automatic
        firstHex = defaults.string(forKey: Self.firstKey) ?? "D6F4FF"
        secondHex = defaults.string(forKey: Self.secondKey) ?? "6D83FF"
    }

    var preferredScheme: ColorScheme? {
        switch mode {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    var firstColor: Color { Color(hex: firstHex) ?? .cyan }
    var secondColor: Color { Color(hex: secondHex) ?? .indigo }

    var textStyle: AnyShapeStyle {
        switch textMode {
        case .automatic:
            return AnyShapeStyle(Color.primary)
        case .solid:
            return AnyShapeStyle(firstColor)
        case .gradient:
            return AnyShapeStyle(LinearGradient(
                colors: [firstColor, secondColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
    }

    func wordmarkStyle(for colorScheme: ColorScheme) -> AnyShapeStyle {
        if textMode != .automatic { return textStyle }
        let base: Color = colorScheme == .dark ? .white : .black
        return AnyShapeStyle(LinearGradient(
            colors: [base, base.opacity(0.9), Color(red: 0.28, green: 0.72, blue: 0.96)],
            startPoint: .leading,
            endPoint: .trailing
        ))
    }

    func resetTextColors() {
        textMode = .automatic
        firstHex = "D6F4FF"
        secondHex = "6D83FF"
    }
}

extension Color {
    /// Convert a ColorPicker selection to an RGB hex string for persistence.
    var berylliumRGBHex: String {
        let native = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "FFFFFF"
        }
        return String(format: "%02X%02X%02X",
                      Int((min(max(r, 0), 1) * 255).rounded()),
                      Int((min(max(g, 0), 1) * 255).rounded()),
                      Int((min(max(b, 0), 1) * 255).rounded()))
    }
}
