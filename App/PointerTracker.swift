import AppKit
import SwiftUI

/// The pointer position over the floating panel, in the panel's top-left coordinates; nil when outside.
@MainActor
final class PointerTracker: ObservableObject {
    @Published var location: CGPoint?
}

/// SwiftUI hover tracking stays silent in a panel of an app that is never active, so track with `.activeAlways`.
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var tracker: PointerTracker?
    private var pointerArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        tracker?.location = topLeftLocation(of: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        tracker?.location = topLeftLocation(of: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        tracker?.location = nil
    }

    private func topLeftLocation(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
