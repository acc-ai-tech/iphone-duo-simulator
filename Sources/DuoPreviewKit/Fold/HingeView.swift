import UIKit

/// Flat hinge indication: a shaded band whose darkness and width grow as the device folds, plus the angle label.
final class HingeView: UIView {
    private let band = CAGradientLayer()
    private let line = CALayer()
    private let label = PaddedLabel()
    private var axis: DuoHingeAxis = .none
    private var angle: Double = 180
    private var hingeWidth: Double = 0
    private var shadeOpacity: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(band)
        line.backgroundColor = UIColor(white: 0.5, alpha: 0.35).cgColor
        layer.addSublayer(line)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(axis: DuoHingeAxis, angle: Double, config: DuoConfiguration, visible: Bool) {
        self.axis = visible ? axis : .none
        self.angle = angle
        hingeWidth = config.hingeWidth
        shadeOpacity = config.animation.shadeOpacity
        isHidden = self.axis == .none
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard axis != .none else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fold = (180 - angle) / 180 // 0 flat … 1 closed
        let width = hingeWidth * (1 + fold * 5)
        let shade = UIColor.black.withAlphaComponent(0.15 + shadeOpacity * fold).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        band.colors = [clear, shade, clear]
        band.locations = [0, 0.5, 1]
        switch axis {
        case .vertical:
            band.startPoint = CGPoint(x: 0, y: 0.5)
            band.endPoint = CGPoint(x: 1, y: 0.5)
            band.frame = CGRect(x: bounds.midX - width / 2, y: 0, width: width, height: bounds.height)
            line.frame = CGRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
        case .horizontal:
            band.startPoint = CGPoint(x: 0.5, y: 0)
            band.endPoint = CGPoint(x: 0.5, y: 1)
            band.frame = CGRect(x: 0, y: bounds.midY - width / 2, width: bounds.width, height: width)
            line.frame = CGRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        case .none:
            break
        }
        CATransaction.commit()

        label.isHidden = angle >= 179.5
        label.text = "\(Int(angle.rounded()))°"
        label.sizeToFit()
        label.center = axis == .vertical
            ? CGPoint(x: bounds.midX, y: 22)
            : CGPoint(x: bounds.width - label.bounds.width / 2 - 8, y: bounds.midY)
    }
}
