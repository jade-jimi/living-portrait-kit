#if os(macOS)
import AppKit
import LivingPortraitCore
import LivingPortraitSwiftUI
import SwiftUI

/// A small desktop-companion panel. The host app owns lifecycle and persists position if desired.
@MainActor
final class FloatingPortraitPanelController<Portrait: View> {
    private let panel: NSPanel

    init(
        size: CGSize = CGSize(width: 270, height: 480),
        @ViewBuilder portrait: () -> Portrait
    ) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(
            rootView: portrait()
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        )
    }

    func show(near visibleFrame: NSRect? = NSScreen.main?.visibleFrame) {
        if let visibleFrame {
            let margin: CGFloat = 24
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.maxX - panel.frame.width - margin,
                y: visibleFrame.minY + margin
            ))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Minimal menu-bar host example. Keep this adapter in the macOS app, not in WidgetKit.
@MainActor
final class PortraitCompanionCoordinator {
    private var panelController: FloatingPortraitPanelController<BasicLivingPortrait>?

    func toggle(scene: LivingPortraitScene) {
        if let panelController {
            panelController.hide()
            self.panelController = nil
        } else {
            let controller = FloatingPortraitPanelController {
                BasicLivingPortrait(scene: scene)
            }
            controller.show()
            panelController = controller
        }
    }
}
#endif
