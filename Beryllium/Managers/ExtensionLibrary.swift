import Foundation
import SwiftUI
import WebKit

// Imported ZIP archives of standards-based WebExtensions. These are NOT the
// Safari App Extensions installed in other iOS applications.
enum ExtensionKind: String, Codable, CaseIterable, Identifiable {
    case chromium = "Chromium Extensions"
    case safari = "Safari Extensions"
    var id: String { rawValue }
}

struct BerylliumExtension: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var version: String
    var kind: ExtensionKind
    var archiveName: String
    var requestedPermissions: [String]
    var requestedHosts: [String]
}

struct StagedExtension: Identifiable {
    let id = UUID()
    var entry: BerylliumExtension
    var temporaryURL: URL
}

@MainActor final class ExtensionLibrary: ObservableObject {
    static let shared = ExtensionLibrary()

    @Published private(set) var extensions: [BerylliumExtension] = []
    @Published private(set) var enabledBySite: [String: Set<UUID>] = [:]

    private struct DiskState: Codable {
        var extensions: [BerylliumExtension]
        var enabledBySite: [String: Set<UUID>]
    }

    private var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BerylliumExtensions", isDirectory: true)
    }
    private var stateURL: URL { root.appendingPathComponent("library.json") }
    private var archivesURL: URL { root.appendingPathComponent("Archives", isDirectory: true) }

    private init() {
        try? FileManager.default.createDirectory(at: archivesURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(DiskState.self, from: data) else { return }
        extensions = state.extensions
        enabledBySite = state.enabledBySite
    }

    func installed(kind: ExtensionKind) -> [BerylliumExtension] {
        extensions.filter { $0.kind == kind }
    }

    func enabled(_ entry: BerylliumExtension, siteID: UUID) -> Bool {
        enabledBySite[siteID.uuidString]?.contains(entry.id) == true
    }

    func enabledExtensions(siteID: UUID) -> [BerylliumExtension] {
        extensions.filter { enabled($0, siteID: siteID) }
    }

    func setEnabled(_ value: Bool, entry: BerylliumExtension, siteID: UUID) {
        var ids = enabledBySite[siteID.uuidString, default: []]
        if value { ids.insert(entry.id) } else { ids.remove(entry.id) }
        enabledBySite[siteID.uuidString] = ids
        persist()
    }

    func archiveURL(for entry: BerylliumExtension) -> URL {
        archivesURL.appendingPathComponent(entry.archiveName)
    }

    // Stage and validate before presenting requested permissions to the user.
    // Nothing becomes installed or active until confirm(_:) is called.
    func stage(sourceURL: URL, kind: ExtensionKind) async throws -> StagedExtension {
        let fm = FileManager.default
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

        let attrs = try fm.attributesOfItem(atPath: sourceURL.path)
        let byteCount = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount > 0 && byteCount < 40 * 1024 * 1024 else {
            throw ExtensionError.invalid("Extension ZIP must be smaller than 40 MB.")
        }
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            throw ExtensionError.invalid("Import a ZIP containing a manifest.json at its root.")
        }
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try fm.copyItem(at: sourceURL, to: temp)
        do {
            let ext = try await WKWebExtension(resourceBaseURL: temp)
            let permissions = ext.requestedPermissions.map(\.rawValue).sorted()
            let hosts = ext.allRequestedMatchPatterns.map(\.string).sorted()
            let entry = BerylliumExtension(id: UUID(), name: ext.displayName ?? "Unnamed Extension",
                                           version: ext.version ?? "?", kind: kind,
                                           archiveName: UUID().uuidString + ".zip",
                                           requestedPermissions: permissions, requestedHosts: hosts)
            return StagedExtension(entry: entry, temporaryURL: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    func confirm(_ staged: StagedExtension, for siteID: UUID) throws {
        let dest = archiveURL(for: staged.entry)
        try FileManager.default.moveItem(at: staged.temporaryURL, to: dest)
        extensions.append(staged.entry)
        setEnabled(true, entry: staged.entry, siteID: siteID)
    }

    func cancel(_ staged: StagedExtension) {
        try? FileManager.default.removeItem(at: staged.temporaryURL)
    }

    func uninstall(_ entry: BerylliumExtension) {
        extensions.removeAll { $0.id == entry.id }
        for key in enabledBySite.keys {
            enabledBySite[key]?.remove(entry.id)
        }
        try? FileManager.default.removeItem(at: archiveURL(for: entry))
        persist()
    }

    private func persist() {
        let state = DiskState(extensions: extensions, enabledBySite: enabledBySite)
        guard let bytes = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? bytes.write(to: stateURL, options: .atomic)
    }
}

enum ExtensionError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return "Invalid extension."
    }
}
