import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Covers the host and draws the device as snapshot leaves rotated in 3D.
final class FoldOverlayView: UIView {
    private let stage = CALayer()
    private let leafA = CALayer()
    private let leafB = CALayer()
    private let shadeA = CALayer()
    private let shadeB = CALayer()
    private let blurA = CALayer()
    private let blurB = CALayer()
    private var axis: DuoHingeAxis = .none
    private var leafFrame: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(stage)
        for (leaf, blur, shade) in [(leafA, blurA, shadeA), (leafB, blurB, shadeB)] {
            leaf.isDoubleSided = false
            leaf.masksToBounds = true
            leaf.contentsGravity = .resize
            blur.contentsGravity = .resize
            blur.opacity = 0
            leaf.addSublayer(blur)
            shade.backgroundColor = UIColor.black.cgColor
            shade.opacity = 0
            leaf.addSublayer(shade)
            stage.addSublayer(leaf)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `image` (drawn at `frame` in overlay coordinates) as two leaves split by `axis`, or one leaf for `.none`.
    /// `blurred` (same size as `image`) is cross-faded over the leaves by `render(…blur:)`.
    func configure(image: UIImage, blurred: UIImage? = nil, frame: CGRect, axis: DuoHingeAxis, perspective: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        isHidden = false
        self.axis = axis
        leafFrame = frame
        stage.frame = bounds
        var perspectiveTransform = CATransform3DIdentity
        perspectiveTransform.m34 = -1 / perspective
        stage.sublayerTransform = perspectiveTransform

        for leaf in [leafA, leafB] {
            leaf.transform = CATransform3DIdentity
            leaf.contents = image.cgImage
            leaf.contentsScale = image.scale
        }
        for blur in [blurA, blurB] {
            blur.contents = blurred?.cgImage
            blur.opacity = 0
        }
        let w = frame.width, h = frame.height
        switch axis {
        case .vertical:
            place(leafA, anchor: CGPoint(x: 1, y: 0.5), size: CGSize(width: w / 2, height: h),
                  position: CGPoint(x: frame.midX, y: frame.midY), contentsRect: CGRect(x: 0, y: 0, width: 0.5, height: 1))
            place(leafB, anchor: CGPoint(x: 0, y: 0.5), size: CGSize(width: w / 2, height: h),
                  position: CGPoint(x: frame.midX, y: frame.midY), contentsRect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
            leafB.isHidden = false
        case .horizontal:
            place(leafA, anchor: CGPoint(x: 0.5, y: 1), size: CGSize(width: w, height: h / 2),
                  position: CGPoint(x: frame.midX, y: frame.midY), contentsRect: CGRect(x: 0, y: 0, width: 1, height: 0.5))
            place(leafB, anchor: CGPoint(x: 0.5, y: 0), size: CGSize(width: w, height: h / 2),
                  position: CGPoint(x: frame.midX, y: frame.midY), contentsRect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
            leafB.isHidden = false
        case .none:
            place(leafA, anchor: CGPoint(x: 0, y: 0.5), size: frame.size,
                  position: CGPoint(x: frame.minX, y: frame.midY), contentsRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            leafB.isHidden = true
        }
        CATransaction.commit()
    }

    /// Replaces leaf images without changing geometry (live 3D view).
    func updateImage(_ image: UIImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leafA.contents = image.cgImage
        leafB.contents = image.cgImage
        CATransaction.commit()
    }

    /// Rotates leaves by `rotation` degrees each (0 = flat).
    func render(rotation: Double, shadeOpacity: Double, blur: Double = 0) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = rotation * .pi / 180
        let shade = Float(shadeOpacity * sin(r))
        switch axis {
        case .vertical:
            leafA.transform = CATransform3DMakeRotation(r, 0, 1, 0)
            leafB.transform = CATransform3DMakeRotation(-r, 0, 1, 0)
        case .horizontal:
            leafA.transform = CATransform3DMakeRotation(-r, 1, 0, 0)
            leafB.transform = CATransform3DMakeRotation(r, 1, 0, 0)
        case .none:
            leafA.transform = CATransform3DMakeRotation(-r, 0, 1, 0)
        }
        shadeA.opacity = shade
        shadeB.opacity = shade
        blurA.opacity = Float(blur)
        blurB.opacity = Float(blur)
        CATransaction.commit()
    }

    func hide() {
        isHidden = true
        alpha = 1
        leafA.contents = nil
        leafB.contents = nil
        blurA.contents = nil
        blurB.contents = nil
    }

    /// Gaussian blur of a snapshot, same size as the input.
    static func blurred(_ image: UIImage, radius: Double) -> UIImage? {
        guard radius > 0, let cg = image.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = Float(radius * image.scale)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    private func place(_ leaf: CALayer, anchor: CGPoint, size: CGSize, position: CGPoint, contentsRect: CGRect) {
        leaf.anchorPoint = anchor
        leaf.bounds = CGRect(origin: .zero, size: size)
        leaf.position = position
        leaf.contentsRect = contentsRect
        for sublayer in leaf.sublayers ?? [] {
            sublayer.frame = leaf.bounds
            sublayer.contentsRect = contentsRect
        }
    }
}

extension DuoConfiguration {
    /// Rotation of each leaf (degrees) for a hinge angle on the inner screen.
    func innerLeafRotation(angle: Double) -> Double {
        (180 - angle) / 2
    }

    /// Rotation of the single outer leaf; matches the inner leaves at `displaySwitchAngle`.
    func outerLeafRotation(angle: Double) -> Double {
        guard displaySwitchAngle > 0 else { return 0 }
        return min(angle / displaySwitchAngle, 1) * innerLeafRotation(angle: displaySwitchAngle)
    }
}

/// Static 3D half-open view: refreshes leaf snapshots from the live content at `animation.halfOpen3DFPS`.
///
/// Live content cannot be shown on two transformed leaves with public API (see NOTES.md), so the leaves are
/// periodic `drawHierarchy` snapshots and interaction is disabled while this mode is on.
@MainActor
final class LeafSnapshotter {
    private unowned let host: DuoHostViewController
    private var timer: Timer?

    init(host: DuoHostViewController) {
        self.host = host
    }

    func start() {
        render()
        let interval = 1 / max(host.config.animation.halfOpen3DFPS, 1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reconfigures geometry and draws the current angle.
    func render() {
        let config = host.config
        let state = host.displayedState
        let layout = state.layout(in: config)
        let image = host.snapshotDevice(afterScreenUpdates: false)
        host.overlay.configure(image: image, frame: host.bezelView.frame,
                               axis: layout.hingeAxis == .none ? .vertical : layout.hingeAxis,
                               perspective: config.animation.perspective)
        host.overlay.render(rotation: config.innerLeafRotation(angle: state.hingeAngle),
                            shadeOpacity: config.animation.shadeOpacity)
        host.raiseOverlay()
    }

    private func refresh() {
        host.overlay.updateImage(host.snapshotDevice(afterScreenUpdates: false))
    }

    isolated deinit {
        timer?.invalidate()
    }
}
