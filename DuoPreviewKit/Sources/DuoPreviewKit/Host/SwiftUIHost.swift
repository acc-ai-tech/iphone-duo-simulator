import Observation
import SwiftUI
import UIKit

public extension View {
    /// Installs the Duo emulator into the window that hosts this view (once).
    ///
    /// The window's root `UIHostingController` becomes a child of the Duo host. Apply it to the root view
    /// of the `WindowGroup`. No-op when DuoPreview is disabled.
    func duoPreviewHost() -> some View {
        modifier(DuoPreviewHostModifier())
    }
}

struct DuoPreviewHostModifier: ViewModifier {
    func body(content: Content) -> some View {
        if DuoPreview.isEnabled {
            content.background(WindowInstaller().frame(width: 0, height: 0).accessibilityHidden(true))
        } else {
            content
        }
    }
}

private struct WindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            // Defer past the current update pass and the root's appearance transition; replacing
            // rootViewController earlier triggers "Unbalanced calls to begin/end appearance transitions".
            DispatchQueue.main.async { [weak window] in
                DispatchQueue.main.async { [weak window] in
                    guard let window else { return }
                    DuoPreview.install(in: window)
                }
            }
        }
    }
}

/// Fallback host that does not touch the window: sizes its content to the Duo state and injects size classes,
/// safe area and Duo environment values. No device frame, HUD shortcuts only via ``DuoPreview`` API.
///
/// Prefer ``SwiftUI/View/duoPreviewHost()``; see NOTES.md for why.
public struct DuoPreviewHostView<Content: View>: View {
    @State private var model = FallbackModel()
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if DuoPreview.isEnabled {
            let config = DuoConfiguration.current
            let layout = model.state.layout(in: config)
            let insets = layout.safeAreaInsets
            ZStack {
                Color.black.ignoresSafeArea()
                content
                    .safeAreaPadding(EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right))
                    .environment(\.horizontalSizeClass, layout.sizeClass.horizontal == .compact ? .compact : .regular)
                    .environment(\.verticalSizeClass, layout.sizeClass.vertical == .compact ? .compact : .regular)
                    .environment(\.duoPosture, layout.posture)
                    .environment(\.duoHinge, DuoHinge(angle: model.state.hingeAngle, rect: layout.hingeRect))
                    .frame(width: layout.contentFrame.width, height: layout.contentFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
            }
            .task {
                for await state in DuoPreview.stateStream {
                    withAnimation(.easeInOut(duration: config.animation.duration)) { model.state = state }
                }
            }
        } else {
            content
        }
    }
}

@MainActor
@Observable
private final class FallbackModel {
    var state = DuoPreview.state
}
