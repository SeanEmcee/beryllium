import SwiftUI

struct BerylliumWordmark: View {
    @EnvironmentObject private var appearance: BerylliumAppearance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.20, green: 0.83, blue: 0.96),
                                 Color(red: 0.36, green: 0.43, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Text("B")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("Beryllium")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .tracking(-0.45)
                .foregroundStyle(appearance.wordmarkStyle(for: colorScheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beryllium")
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: BerylliumAppearance
    @Environment(\.dismiss) private var dismiss

    private var firstSelection: Binding<Color> {
        Binding(
            get: { appearance.firstColor },
            set: { appearance.firstHex = $0.berylliumRGBHex }
        )
    }

    private var secondSelection: Binding<Color> {
        Binding(
            get: { appearance.secondColor },
            set: { appearance.secondHex = $0.berylliumRGBHex }
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
                    Text("Dark is the default. System follows your iPhone's appearance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Font colors") {
                    Picker("Text style", selection: $appearance.textMode) {
                        ForEach(BerylliumTextMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    if appearance.textMode == .solid || appearance.textMode == .gradient {
                        ColorPicker("Text color", selection: firstSelection, supportsOpacity: false)
                    }
                    if appearance.textMode == .gradient {
                        ColorPicker("Gradient end color", selection: secondSelection, supportsOpacity: false)
                    }
                    HStack {
                        Text("Beryllium preview")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(appearance.textStyle)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button("Restore automatic text colors") {
                        appearance.resetTextColors()
                    }
                } footer: {
                    Text("Changes apply to Beryllium's native interface, not the webpages inside shortcuts.")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
