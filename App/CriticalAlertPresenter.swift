import AppKit

/// Shows the critical-limit dialog as a normal window: `runModal()` would hold the main queue, and every refresh with it.
@MainActor
final class CriticalAlertPresenter: NSObject {
    private var alert: NSAlert?

    func show(text: String) {
        if let alert {
            alert.informativeText = text
            alert.layout()
            alert.window.orderFrontRegardless()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Critical gas limit reached"
        alert.informativeText = text
        let ok = alert.addButton(withTitle: "OK")
        ok.target = self
        ok.action = #selector(close)
        alert.layout()
        alert.window.level = .floating
        alert.window.hidesOnDeactivate = false
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        alert.window.center()
        self.alert = alert
        // Not key and no activation: a Return typed in another app must not press OK unseen.
        alert.window.orderFrontRegardless()
    }

    @objc private func close() {
        alert?.window.orderOut(nil)
        alert = nil
    }
}
