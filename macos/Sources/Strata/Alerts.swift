// SPDX-License-Identifier: MIT

import AppKit

@MainActor
enum Alerts {
    static func showError(_ message: String, detail: String? = nil, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail ?? ""
        alert.addButton(withTitle: tr("Close"))
        present(alert, window: window) { _ in }
    }

    /// Asks before a destructive action. Cancel is the default button.
    static func confirmDestructive(
        _ message: String, detail: String, action: String, window: NSWindow?,
        onConfirm: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: tr("Cancel"))
        let destructive = alert.addButton(withTitle: action)
        destructive.hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = "\r"
        destructive.keyEquivalent = ""
        present(alert, window: window) { response in
            if response == .alertSecondButtonReturn { onConfirm() }
        }
    }

    static func present(
        _ alert: NSAlert, window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}
