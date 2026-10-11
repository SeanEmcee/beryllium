import SwiftUI

/// Per-interface-area, independently persisted typography with positional color stops.
struct BerylliumStyledText: View {
    @EnvironmentObject private var appearance: BerylliumAppearance
    @Environment(\.colorScheme) private var colorScheme
    let value: String
    let area: TypographyArea

    var body: some View {
        let style = appearance.style(for: area)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: style.shader == .none)) { timeline in
            HStack(spacing: 0) {
                if style.selectionLength > 0 {
                    let chars = Array(value)
                    let start = min(max(0, style.selectionStart), chars.count)
                    let end = min(chars.count, start + max(0, style.selectionLength))
                    if start > 0 {
                        plain(String(chars[..<start]), style: style)
                    }
                    decorated(String(chars[start..<end]), style: style, time: timeline.date.timeIntervalSinceReferenceDate)
                    if end < chars.count {
                        plain(String(chars[end...]), style: style)
                    }
                } else {
                    decorated(value, style: style, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value)
    }

    private func plain(_ string: String, style: TypographyStyle) -> some View {
        Text(string)
            .font(.system(size: CGFloat(style.fontSize), weight: style.heavy ? .bold : .regular, design: .rounded))
            .foregroundStyle(.primary)
    }

    private func decorated(_ string: String, style: TypographyStyle, time: TimeInterval) -> some View {
        Text(string)
            .font(.system(size: CGFloat(style.fontSize), weight: style.heavy ? .bold : .regular, design: .rounded))
            .foregroundStyle(style.fillStyle(for: colorScheme, wordmark: area == .wordmark))
            // Eight one-direction offset shadows form a subtle adjustable outline
            // without changing text layout or relying on a custom font renderer.
            .shadow(color: outline(style), radius: 0, x: CGFloat(style.outlineWidth), y: 0)
            .shadow(color: outline(style), radius: 0, x: -CGFloat(style.outlineWidth), y: 0)
            .shadow(color: outline(style), radius: 0, x: 0, y: CGFloat(style.outlineWidth))
            .shadow(color: outline(style), radius: 0, x: 0, y: -CGFloat(style.outlineWidth))
            .shadow(color: outline(style), radius: 0, x: CGFloat(style.outlineWidth) * 0.7, y: CGFloat(style.outlineWidth) * 0.7)
            .shadow(color: outline(style), radius: 0, x: -CGFloat(style.outlineWidth) * 0.7, y: CGFloat(style.outlineWidth) * 0.7)
            .shadow(color: outline(style), radius: 0, x: CGFloat(style.outlineWidth) * 0.7, y: -CGFloat(style.outlineWidth) * 0.7)
            .shadow(color: outline(style), radius: 0, x: -CGFloat(style.outlineWidth) * 0.7, y: -CGFloat(style.outlineWidth) * 0.7)
            .colorEffect(
                ShaderLibrary.berylliumTypographyFX(
                    .float(Float(time * style.shaderSpeed)),
                    .float(Float(style.shaderStrength)),
                    .float(style.shader.number)
                ),
                isEnabled: style.shader != .none
            )
    }

    private func outline(_ style: TypographyStyle) -> Color {
        style.outlineWidth <= 0 ? .clear : (Color(hex: style.outlineHex) ?? .black)
    }
}

struct BerylliumWordmark: View {
    var body: some View {
        BerylliumStyledText(value: "Beryllium", area: .wordmark)
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: BerylliumAppearance
    @Environment(\.dismiss) private var dismiss
    @State private var area: TypographyArea = .wordmark

    private var selectedStyle: Binding<TypographyStyle> {
        Binding(
            get: { appearance.style(for: area) },
            set: { appearance.save($0, for: area) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Interface") {
                    Picker("Appearance", selection: $appearance.mode) {
                        ForEach(BerylliumAppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Choose text area") {
                    Picker("Customize", selection: $area) {
                        ForEach(TypographyArea.allCases) { entry in
                            Text(entry.rawValue).tag(entry)
                        }
                    }
                    BerylliumStyledText(value: area.example, area: area)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .padding(.vertical, 8)
                }
                TypographyAreaEditor(area: area, style: selectedStyle)
                Section {
                    Button("Reset selected text area") { appearance.reset(area) }
                } footer: {
                    Text("Only the selected native Beryllium text area changes. Websites loaded inside shortcuts keep their own styles. Animated shaders render on the device GPU.")
                }
            }
            .navigationTitle("Typography Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct TypographyAreaEditor: View {
    let area: TypographyArea
    @Binding var style: TypographyStyle

    private var outlineSelection: Binding<Color> {
        Binding(get: { Color(hex: style.outlineHex) ?? .black },
                set: { style.outlineHex = $0.berylliumRGBHex })
    }
    var body: some View {
        Section("Font") {
            HStack {
                Text("Size")
                Spacer()
                Text("\(Int(style.fontSize)) pt").foregroundStyle(.secondary)
            }
            Slider(value: $style.fontSize, in: 10...42, step: 1)
            Toggle("Bold", isOn: $style.heavy)
            Picker("Text fill", selection: $style.mode) {
                ForEach(BerylliumTextMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
        }

        if style.mode != .automatic {
            Section("Gradient stops") {
                if style.mode == .gradient {
                    Text("Move each stop to control exactly where colors blend. Dragging stops past one another changes the color order.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($style.stops) { $stop in
                    GradientStopEditor(stop: $stop, allowRemoval: style.stops.count > 2 && style.mode == .gradient) {
                        let target = stop.id
                        style.stops.removeAll { $0.id == target }
                    }
                }
                if style.mode == .gradient {
                    Button {
                        guard style.stops.count < 12 else { return }
                        style.stops.append(TextGradientStop(hex: "43E0FD", position: 0.5))
                    } label: {
                        Label("Add color stop", systemImage: "plus.circle")
                    }
                    .disabled(style.stops.count >= 12)
                    HStack {
                        Text("Direction")
                        Spacer()
                        Text("\(Int(style.angle))°").foregroundStyle(.secondary)
                    }
                    Slider(value: $style.angle, in: 0...360, step: 5)
                }
            }
        }

        Section("Outline") {
            HStack {
                Text("Thickness")
                Spacer()
                Text(String(format: "%.1f pt", style.outlineWidth)).foregroundStyle(.secondary)
            }
            Slider(value: $style.outlineWidth, in: 0...3, step: 0.25)
            if style.outlineWidth > 0 {
                ColorPicker("Outline color", selection: outlineSelection, supportsOpacity: false)
            }
        }

        Section("GPU shader") {
            Picker("Effect", selection: $style.shader) {
                ForEach(TextShaderEffect.allCases) { item in Text(item.rawValue).tag(item) }
            }
            if style.shader != .none {
                HStack { Text("Strength"); Spacer(); Text("\(Int(style.shaderStrength * 100))%") }
                Slider(value: $style.shaderStrength, in: 0...1, step: 0.05)
                HStack { Text("Speed"); Spacer(); Text(String(format: "%.1fx", style.shaderSpeed)) }
                Slider(value: $style.shaderSpeed, in: 0.25...3, step: 0.25)
            }
        }

        Section("Character selection") {
            Text("Choose just part of the selected text area. Set length to zero to style the whole label.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Start at character \(style.selectionStart + 1)", value: $style.selectionStart, in: 0...100)
            Stepper("Styled characters: \(style.selectionLength == 0 ? "All" : String(style.selectionLength))",
                    value: $style.selectionLength, in: 0...100)
        }
    }
}

private struct GradientStopEditor: View {
    @Binding var stop: TextGradientStop
    let allowRemoval: Bool
    let remove: () -> Void
    private var selection: Binding<Color> {
        Binding(get: { Color(hex: stop.hex) ?? .cyan }, set: { stop.hex = $0.berylliumRGBHex })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ColorPicker("Color", selection: selection, supportsOpacity: false)
                if allowRemoval { Button(role: .destructive, action: remove) { Image(systemName: "minus.circle.fill") } }
            }
            HStack {
                Text("Position")
                Spacer()
                Text("\(Int(stop.position * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $stop.position, in: 0...1, step: 0.01)
        }
        .padding(.vertical, 4)
    }
}
