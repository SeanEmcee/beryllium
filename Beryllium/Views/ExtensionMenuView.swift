import SwiftUI

struct ExtensionMenuView: View {
    @ObservedObject var runtime: ExtensionRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Active on this website") {
                    ForEach(runtime.running) { item in
                        Button {
                            dismiss()
                            // Give the menu time to dismiss before WebKit presents
                            // the extension's own action popup.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                runtime.activate(item)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "puzzlepiece.extension")
                                VStack(alignment: .leading) {
                                    Text(item.entry.name).foregroundStyle(.primary)
                                    Text(item.entry.kind.rawValue).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                    if runtime.running.isEmpty {
                        Text("No extensions loaded for this site.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !runtime.errors.isEmpty {
                    Section("Load errors") {
                        ForEach(runtime.errors, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("Extensions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
