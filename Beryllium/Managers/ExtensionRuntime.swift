import Foundation
import SwiftUI
import UIKit
import WebKit

// One controller per open website. Only extensions enabled for that site are
// loaded; another website does not inherit their privileges or content scripts.
@MainActor final class ExtensionRuntime: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    struct RunningExtension: Identifiable {
        let entry: BerylliumExtension
        let context: WKWebExtensionContext
        var id: UUID { entry.id }
    }

    @Published private(set) var isPrepared = false
    @Published private(set) var running: [RunningExtension] = []
    @Published private(set) var errors: [String] = []
    @Published private(set) var enabledCount = 0

    private(set) var controller: WKWebExtensionController?

    func prepare(siteID: UUID) async {
        isPrepared = false
        let entries = ExtensionLibrary.shared.enabledExtensions(siteID: siteID)
        enabledCount = entries.count
        running = []
        errors = []
        guard !entries.isEmpty else {
            controller = nil
            isPrepared = true
            return
        }

        let host = WKWebExtensionController()
        host.delegate = self
        controller = host
        for entry in entries {
            do {
                let extensionObject = try await WKWebExtension(
                    resourceBaseURL: ExtensionLibrary.shared.archiveURL(for: entry)
                )
                let context = WKWebExtensionContext(for: extensionObject)
                context.uniqueIdentifier = entry.id.uuidString
                // The explicit "Install & Allow" confirmation in the importer
                // is required BEFORE these permissions are assigned. Optional
                // permissions are not granted here.
                for permission in extensionObject.requestedPermissions {
                    context.setPermissionStatus(.grantedExplicitly, for: permission)
                }
                for pattern in extensionObject.allRequestedMatchPatterns {
                    context.setPermissionStatus(.grantedExplicitly, for: pattern)
                }
                try host.load(context)
                running.append(RunningExtension(entry: entry, context: context))
            } catch {
                errors.append("\(entry.name): \(error.localizedDescription)")
            }
        }
        isPrepared = true
    }

    // Present the extension's actual WebKit-provided popup, if available.
    func activate(_ item: RunningExtension) {
        item.context.performAction(for: nil)
    }

    private func frontController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        guard action.presentsPopup, let popup = action.popupViewController,
              let top = frontController() else {
            completionHandler(nil)
            return
        }
        top.present(popup, animated: true) { completionHandler(nil) }
    }

    // Runtime requests that were NOT covered by the installation consent are
    // shown to the person, not silently granted.
    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let names = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        confirm(title: "Extension permission", description: names) { approved in
            completionHandler(approved ? permissions : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let names = patterns.map(\.string).sorted().joined(separator: "\n")
        confirm(title: "Website access", description: names) { approved in
            completionHandler(approved ? patterns : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?,
                                for context: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let names = urls.map(\.absoluteString).sorted().joined(separator: "\n")
        confirm(title: "Access requested", description: names) { approved in
            completionHandler(approved ? urls : [], nil)
        }
    }

    private func confirm(title: String, description: String, completion: @escaping (Bool) -> Void) {
        guard let presenter = frontController() else { completion(false); return }
        let alert = UIAlertController(title: title, message: description, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in completion(true) })
        presenter.present(alert, animated: true)
    }
}
