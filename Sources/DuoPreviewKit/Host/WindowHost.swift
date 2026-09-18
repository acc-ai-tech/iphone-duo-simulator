import UIKit

/// Hosts the app by resizing its own window to the emulated screen instead of reparenting its root controller.
///
/// The device chrome (frame, placeholder, info) is drawn in a window below; the hinge line and the right toolbar are
/// added to the app window above its content. Nothing in the app's view hierarchy is touched, so app state survives.
@MainActor
final class WindowHost {
    let appWindow: UIWindow
    let chromeWindow: UIWindow
    /// Fold leaves and the 3D badge are drawn above the app's window, so the live app never has to be hidden.
    let overlayWindow: HUDWindow
    let host: DuoHostViewController
    /// Hinge line and right toolbar live above the app content, so they are added to the app window.
    private let hingeOverlay = HingeView()

    init?(appWindow: UIWindow, runtime: DuoRuntime) {
        guard let scene = appWindow.windowScene else { return nil }
        self.appWindow = appWindow
        chromeWindow = UIWindow(windowScene: scene)
        chromeWindow.windowLevel = .normal - 1
        overlayWindow = HUDWindow(windowScene: scene)
        overlayWindow.windowLevel = .normal + 1
        overlayWindow.backgroundColor = .clear
        overlayWindow.rootViewController = UIViewController()
        overlayWindow.isHidden = false
        host = DuoHostViewController(child: nil, runtime: runtime)
        host.contentController = appWindow.rootViewController
        chromeWindow.rootViewController = host
        chromeWindow.isHidden = false

        appWindow.clipsToBounds = true
        appWindow.layer.cornerCurve = .continuous
        hingeOverlay.isUserInteractionEnabled = false
        appWindow.addSubview(hingeOverlay)
        host.sideToolbar.view.removeFromSuperview()
        appWindow.addSubview(host.sideToolbar.view)
        host.hingeView.isHidden = true

        if let container = overlayWindow.rootViewController?.view {
            host.moveOverlay(to: container)
            overlayWindow.panel = container.subviews.last
        }
        host.onGeometryChange = { [weak self] geometry in
            self?.apply(geometry)
        }
        host.loadViewIfNeeded()
        host.view.layoutIfNeeded()
    }

    /// Moves the app window onto the content area and lays out the overlays inside it.
    private func apply(_ geometry: DuoGeometry) {
        guard let screen = host.contentContainer.superview else { return }
        let frameInChrome = screen.convert(geometry.contentFrame, to: nil)
        let scale = host.bezelView.transform.a
        appWindow.transform = .identity
        appWindow.bounds = CGRect(origin: .zero, size: geometry.contentFrame.size)
        appWindow.center = CGPoint(x: frameInChrome.midX, y: frameInChrome.midY)
        appWindow.transform = CGAffineTransform(scaleX: scale, y: scale)
        appWindow.layer.cornerRadius = host.config.cornerRadius

        // The hinge belongs to the screen, so lay the overlay out in screen coordinates shifted into the window.
        hingeOverlay.frame = CGRect(origin: CGPoint(x: -geometry.contentFrame.minX, y: -geometry.contentFrame.minY),
                                    size: geometry.screenSize)
        hingeOverlay.update(axis: geometry.angle >= host.config.displaySwitchAngle ? geometry.hingeAxis : .none,
                            angle: geometry.angle, config: host.config,
                            visible: host.runtime.options.showHinge)
        appWindow.bringSubviewToFront(hingeOverlay)

        let toolbarWidth = host.sideToolbar.width
        host.sideToolbar.view.frame = CGRect(x: appWindow.bounds.width - toolbarWidth, y: 0,
                                             width: toolbarWidth, height: appWindow.bounds.height)
        appWindow.bringSubviewToFront(host.sideToolbar.view)

        if let container = overlayWindow.rootViewController?.view {
            host.layoutMovedOverlay(in: container)
        }
    }

    /// Image of the app window content, used to build fold leaves.
    func contentSnapshot(afterScreenUpdates: Bool) -> UIImage {
        UIGraphicsImageRenderer(bounds: appWindow.bounds).image { _ in
            _ = appWindow.drawHierarchy(in: appWindow.bounds, afterScreenUpdates: afterScreenUpdates)
        }
    }

    func restore() {
        appWindow.transform = .identity
        appWindow.frame = chromeWindow.bounds
        appWindow.layer.cornerRadius = 0
        appWindow.clipsToBounds = false
        hingeOverlay.removeFromSuperview()
        host.sideToolbar.view.removeFromSuperview()
        chromeWindow.isHidden = true
        overlayWindow.isHidden = true
    }
}
