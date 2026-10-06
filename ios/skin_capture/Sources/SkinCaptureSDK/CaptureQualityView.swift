#if canImport(UIKit)
import UIKit

final class CaptureQualityBadge: UIView {
    private let circle = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let statusLabel = UILabel()
    private(set) var state: CaptureQualityState = .unknown
    private let name: String

    init(name: String, symbol: String) {
        self.name = name
        super.init(frame: .zero)
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.layer.cornerRadius = 30
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        label.text = name
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .lightGray
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)
        addSubview(label)
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: 60),
            circle.heightAnchor.constraint(equalTo: circle.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            label.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityLabel = name
        update(.unknown)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("請使用程式建立狀態指示器") }

    func update(_ state: CaptureQualityState) {
        self.state = state
        switch state {
        case .unknown:
            circle.backgroundColor = UIColor(white: 0.25, alpha: 1)
            accessibilityValue = "等待辨識"
            statusLabel.text = "待辨識"
        case .passed:
            circle.backgroundColor = UIColor(red: 0, green: 0.8, blue: 0.43, alpha: 1)
            accessibilityValue = "符合"
            statusLabel.text = "符合"
        case .failed:
            circle.backgroundColor = UIColor(red: 0.94, green: 0.28, blue: 0.24, alpha: 1)
            accessibilityValue = "需要調整"
            statusLabel.text = "需調整"
        }
    }
}

final class CaptureQualityView: UIStackView {
    let lighting = CaptureQualityBadge(name: "光線", symbol: "sun.max")
    let angle = CaptureQualityBadge(name: "臉角度", symbol: "face.smiling")
    let size = CaptureQualityBadge(name: "臉大小", symbol: "arrow.left.and.right")

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        distribution = .fillEqually
        spacing = 12
        [lighting, angle, size].forEach(addArrangedSubview)
        accessibilityIdentifier = "capture.quality"
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("請使用程式建立狀態列") }

    func update(_ quality: CaptureQuality) {
        lighting.update(quality.lighting)
        angle.update(quality.angle)
        size.update(quality.size)
    }
}
#endif
