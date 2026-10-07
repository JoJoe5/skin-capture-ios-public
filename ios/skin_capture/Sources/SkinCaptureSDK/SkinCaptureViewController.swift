#if canImport(UIKit)
import AVFoundation
import UIKit

/// 完成回呼只執行一次；success(nil) 表示使用者取消。
public final class SkinCaptureViewController: UIViewController {
    private let configuration: CaptureConfiguration
    private let appearance: CaptureAppearance
    private let completion: (Result<SkinCaptureResult?, SkinCaptureError>) -> Void
    private let camera: CameraService
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let previewMask = CAShapeLayer()
    private var sourceImageSize = CGSize(width: 3, height: 4)
    private let outlineView = UIView()
    private let outlines = (0..<4).map { _ in CAShapeLayer() }
    private let titleLabel = UILabel()
    private let header = UIStackView()
    private let footer = UIStackView()
    private let previewArea = UILayoutGuide()
    let cameraViewport = UIView()
    let qualityView = CaptureQualityView()
    let guidanceLabel = UILabel()
    let detailLabel = UILabel()
    private let imageView = UIImageView()
    private let confirmButton = UIButton(type: .system)
    private let retakeButton = UIButton(type: .system)
    private let retryButton = UIButton(type: .system)
    private var countdownTimer: Timer?
    private var countdown = CaptureCountdown()
    private var lastGuidanceAt: TimeInterval?
    private var pendingPhoto: SkinCaptureResult?
    private var finished = false
    private var visible = false
    private var error: SkinCaptureError?
    private var observers: [NSObjectProtocol] = []

    public init(configuration: CaptureConfiguration = .init(), appearance: CaptureAppearance = .init(),
                completion: @escaping (Result<SkinCaptureResult?, SkinCaptureError>) -> Void) {
        self.configuration = configuration
        self.appearance = appearance
        self.completion = completion
        camera = CameraService(configuration: configuration)
        previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("請使用公開初始化介面") }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    public override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        camera.onGuidance = { [weak self] in self?.update($0) }
        camera.onPhoto = { [weak self] in self?.showPhoto($0) }
        camera.onError = { [weak self] in self?.showError($0) }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.cancelCountdown()
            self?.camera.stop()
            self?.resetGuidance()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self, self.visible, !self.finished, self.pendingPhoto == nil, self.error == nil else { return }
            self.resetGuidance()
            self.camera.start()
        })
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        if pendingPhoto == nil, error == nil, !finished { camera.start() }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        cancelCountdown()
        camera.stop()
    }

    deinit {
        countdownTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 橢圓只裁切預覽；Vision 分析及回傳 JPEG 仍使用完整影像。
        let available = previewArea.layoutFrame
        let width = max(1, min(available.width, available.height * 0.8))
        let height = width / 0.8
        cameraViewport.frame = CGRect(x: available.midX - width / 2, y: available.midY - height / 2,
                                      width: width, height: height)
        outlineView.frame = cameraViewport.frame
        previewLayer.frame = CapturePreviewGeometry.imageRect(in: cameraViewport.bounds.insetBy(dx: 3, dy: 3),
                                                              imageSize: sourceImageSize)
        previewLayer.videoGravity = .resizeAspect
        if let connection = previewLayer.connection {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        previewMask.frame = cameraViewport.bounds
        previewMask.path = UIBezierPath(ovalIn: cameraViewport.bounds.insetBy(dx: 7, dy: 7)).cgPath
        for outline in outlines {
            outline.frame = outlineView.bounds
            outline.path = UIBezierPath(ovalIn: outlineView.bounds.insetBy(dx: 3, dy: 3)).cgPath
        }
        let photoTop = header.frame.maxY + 16
        imageView.frame = CGRect(x: 16, y: photoTop, width: view.bounds.width - 32,
                                 height: max(1, footer.frame.minY - photoTop - 16))
    }

    private func buildUI() {
        view.backgroundColor = .black
        cameraViewport.accessibilityIdentifier = "capture.preview"
        cameraViewport.layer.addSublayer(previewLayer)
        cameraViewport.layer.mask = previewMask
        view.addSubview(cameraViewport)
        outlineView.isUserInteractionEnabled = false
        for (index, outline) in outlines.enumerated() {
            outline.fillColor = UIColor.clear.cgColor
            outline.strokeColor = UIColor(white: 0.32, alpha: 1).cgColor
            outline.lineWidth = 5
            outline.lineCap = .round
            outline.strokeStart = CGFloat(index) / 4 + 0.004
            outline.strokeEnd = CGFloat(index + 1) / 4 - 0.004
            outlineView.layer.addSublayer(outline)
        }
        view.addSubview(outlineView)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)), for: .normal)
        close.tintColor = .white
        close.accessibilityLabel = "取消拍攝"
        close.accessibilityIdentifier = "capture.cancel"
        close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        titleLabel.text = appearance.title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        let spacer = UIView()
        [close, titleLabel, spacer].forEach(header.addArrangedSubview)
        header.axis = .horizontal
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        qualityView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(qualityView)

        guidanceLabel.textColor = .white
        guidanceLabel.font = .preferredFont(forTextStyle: .title3)
        guidanceLabel.numberOfLines = 2
        guidanceLabel.textAlignment = .center
        guidanceLabel.accessibilityTraits = .updatesFrequently
        guidanceLabel.accessibilityIdentifier = "capture.guidance"
        detailLabel.textColor = UIColor(white: 0.45, alpha: 1)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.numberOfLines = 2
        detailLabel.textAlignment = .center
        for label in [titleLabel, guidanceLabel, detailLabel] { label.adjustsFontForContentSizeCategory = true }
        configureButton(confirmButton, title: appearance.confirmText, action: #selector(confirm))
        configureButton(retakeButton, title: appearance.retakeText, action: #selector(retake))
        configureButton(retryButton, title: "重試", action: #selector(retry))
        confirmButton.isHidden = true
        retakeButton.isHidden = true
        retryButton.isHidden = true
        [guidanceLabel, detailLabel, confirmButton, retakeButton, retryButton].forEach(footer.addArrangedSubview)
        footer.axis = .vertical
        footer.spacing = 16
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)
        view.addLayoutGuide(previewArea)

        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.backgroundColor = .black
        view.insertSubview(imageView, belowSubview: header)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 44),
            spacer.widthAnchor.constraint(equalTo: close.widthAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.heightAnchor.constraint(equalToConstant: 44),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            qualityView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            qualityView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            qualityView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            qualityView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            previewArea.topAnchor.constraint(equalTo: qualityView.bottomAnchor, constant: 24),
            previewArea.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -24),
            previewArea.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            previewArea.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        resetGuidance()
    }

    private func configureButton(_ button: UIButton, title: String, action: Selector) {
        var style = UIButton.Configuration.filled()
        style.title = title
        style.baseBackgroundColor = appearance.accentColor
        style.baseForegroundColor = .white
        style.cornerStyle = .medium
        style.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        button.configuration = style
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// 與相機啟停分開，可直接驗證同時顯示的三項狀態與版面。
    func renderGuidance(_ evaluation: GuidanceEvaluation) {
        if let imageSize = evaluation.sourceImageSize, imageSize != sourceImageSize {
            sourceImageSize = imageSize
            view.setNeedsLayout()
        }
        qualityView.update(evaluation.quality, yawDegrees: evaluation.yawDegrees,
                           targetYawDegrees: configuration.targetYawDegrees, poseReliable: evaluation.poseReliable)
        outlines.forEach { $0.strokeColor = (evaluation.canCapture ? appearance.accentColor : UIColor(white: 0.32, alpha: 1)).cgColor }
        setHint(evaluation.blockingGuidance ?? evaluation.guidance, yawDegrees: evaluation.yawDegrees,
                poseReliable: evaluation.poseReliable)
    }

    private func setHint(_ guidance: CaptureGuidance, yawDegrees: Double? = nil, poseReliable: Bool = false) {
        let hint: (String, String)
        let target = String(format: "%+.0f", configuration.targetYawDegrees)
        switch guidance {
        case .noFace:
            hint = ("暫時無法辨識人臉", configuration.targetYawDegrees == 0
                ? "請正面面向鏡頭，露出完整臉部" : "請將臉部放入框內，目標轉頭 \(target)°")
        case .multipleFaces: hint = ("請只保留一張臉", "畫面中不要有其他人")
        case .moveCloser: hint = ("距離太遠", "近一點")
        case .moveAway: hint = ("距離太近", "遠一點")
        case .centerFace: hint = ("臉部未置中", "移到橢圓中央")
        case .faceForward:
            if yawDegrees == nil {
                hint = ("角度尚未辨識", "先面向鏡頭，再慢慢轉頭至 \(target)°")
            } else if !poseReliable {
                hint = ("角度尚待確認", "保持臉部清楚，慢慢轉頭至 \(target)°")
            } else if configuration.targetYawDegrees == 0 {
                hint = ("臉部角度不正", "面向鏡頭，保持頭部端正")
            } else {
                let current = yawDegrees.map { "目前 \(String(format: "%+.0f", $0))°；" } ?? ""
                hint = ("請調整臉部角度", "\(current)目標 \(target)°，保持頭部端正")
            }
        case .moreLight: hint = ("光線不足", "面向明亮且均勻的光源")
        case .lessLight: hint = ("光線太強", "避開直射光")
        case .holdStill: hint = ("請保持不動", "符合條件後自動拍攝")
        case .ready: hint = ("準備完成", "保持不動，即將自動拍攝")
        }
        guidanceLabel.text = appearance.guidanceMessages[guidance.rawValue] ?? hint.0
        detailLabel.text = hint.1
    }

    private func resetGuidance() {
        guard pendingPhoto == nil, error == nil else { return }
        lastGuidanceAt = nil
        renderGuidance(GuidanceEvaluation(guidance: .noFace, progress: 0))
    }

    private func update(_ evaluation: GuidanceEvaluation) {
        guard visible, !finished, pendingPhoto == nil, error == nil else { return }
        lastGuidanceAt = CACurrentMediaTime()
        renderGuidance(evaluation)
        if evaluation.guidance == .ready {
            if evaluation.canCapture {
                countdown.setPaused(false, at: CACurrentMediaTime())
                if countdownTimer == nil { beginCountdown() }
                else { tickCountdown() }
            } else {
                countdown.setPaused(true, at: CACurrentMediaTime())
                detailLabel.text = "\(detailLabel.text ?? "保持不動")，恢復後繼續倒數"
            }
        } else { cancelCountdown() }
    }

    private func beginCountdown() {
        countdown.start(at: CACurrentMediaTime())
        tickCountdown()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickCountdown() }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tickCountdown() {
        guard let lastGuidanceAt, CACurrentMediaTime() - lastGuidanceAt < 0.5 else {
            cancelCountdown()
            renderGuidance(GuidanceEvaluation(guidance: .holdStill, progress: 0))
            return
        }
        guard let remaining = countdown.remaining(at: CACurrentMediaTime(), duration: configuration.countdownDuration) else { return }
        if remaining <= 0 {
            cancelCountdown()
            guidanceLabel.text = "正在拍攝…"
            detailLabel.text = "請稍候"
            camera.capture()
        } else {
            guidanceLabel.text = "保持不動"
            detailLabel.text = "\(Int(ceil(remaining))) 秒後拍攝"
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown.reset()
    }

    private func showPhoto(_ photo: SkinCaptureResult) {
        guard !finished, visible else { return }
        cancelCountdown()
        pendingPhoto = photo
        imageView.image = UIImage(data: photo.jpegData)
        imageView.isHidden = false
        cameraViewport.isHidden = true
        outlineView.isHidden = true
        qualityView.isHidden = true
        titleLabel.text = "確認照片"
        guidanceLabel.text = "確認照片"
        detailLabel.text = "確認後交由 App 處理"
        confirmButton.isHidden = false
        retakeButton.isHidden = false
        view.setNeedsLayout()
    }

    private func showError(_ error: SkinCaptureError) {
        guard !finished else { return }
        cancelCountdown()
        self.error = error
        qualityView.update(.unknown)
        outlines.forEach { $0.strokeColor = UIColor(white: 0.32, alpha: 1).cgColor }
        guidanceLabel.text = error.localizedDescription
        detailLabel.text = error == .permissionDenied ? "允許相機權限後，回到此畫面按重試" : "可重試，或取消拍攝"
        retryButton.isHidden = false
        retryButton.setTitle(error == .permissionDenied ? "開啟設定／重試" : "重試", for: .normal)
    }

    @objc private func confirm() {
        guard let pendingPhoto else { return }
        finish(.success(pendingPhoto))
    }

    @objc private func retake() {
        pendingPhoto = nil
        imageView.image = nil
        imageView.isHidden = true
        cameraViewport.isHidden = false
        outlineView.isHidden = false
        qualityView.isHidden = false
        titleLabel.text = appearance.title
        confirmButton.isHidden = true
        retakeButton.isHidden = true
        resetGuidance()
        view.setNeedsLayout()
        camera.start()
    }

    @objc private func retry() {
        if error == .permissionDenied, AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        error = nil
        retryButton.isHidden = true
        resetGuidance()
        camera.start()
    }

    @objc private func cancel() {
        if let error { finish(.failure(error)) }
        else { finish(.success(nil)) }
    }

    private func finish(_ result: Result<SkinCaptureResult?, SkinCaptureError>) {
        guard !finished else { return }
        finished = true
        cancelCountdown()
        camera.stop()
        completion(result)
    }
}
#endif
