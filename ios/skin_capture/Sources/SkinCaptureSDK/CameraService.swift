#if canImport(UIKit)
import AVFoundation
import UIKit
import Vision

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onGuidance: ((GuidanceEvaluation) -> Void)?
    var onPhoto: ((SkinCaptureResult) -> Void)?
    var onError: ((SkinCaptureError) -> Void)?

    private let configuration: CaptureConfiguration
    private let sessionQueue = DispatchQueue(label: "com.skincapture.session")
    private let analysisQueue = DispatchQueue(label: "com.skincapture.analysis")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    // 下列三項只在主執行緒存取。
    private var activeToken: UUID?
    private var takingPhoto = false
    private var lastReadyAt: TimeInterval?
    // 下列狀態只在相機佇列存取。
    private var configured = false
    private var photoDelegates: [Int64: PhotoDelegate] = [:]
    // 下列狀態只在分析佇列存取。
    private var analysisToken: UUID?
    private var evaluator: GuidanceEvaluator
    private let regionTracker = FaceRegionTracker()
    private var lastAnalysis: TimeInterval = -.infinity
    private var observers: [NSObjectProtocol] = []

    init(configuration: CaptureConfiguration) {
        self.configuration = configuration
        evaluator = GuidanceEvaluator(configuration: configuration)
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) {
                [weak self] _ in
                guard let self, self.activeToken != nil else { return }
                self.stop()
                self.onError?(.interrupted)
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        let retainedSession = session
        sessionQueue.async { if retainedSession.isRunning { retainedSession.stopRunning() } }
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeToken == nil else { return }
        guard configuration.isValid else { onError?(.invalidConfiguration); return }
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
              !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onError?(.missingCameraUsageDescription)
            return
        }
        let token = UUID()
        activeToken = token
        takingPhoto = false
        lastReadyAt = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: activate(token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.activeToken == token else { return }
                    if allowed { self.activate(token) }
                    else { self.fail(.permissionDenied, token: token) }
                }
            }
        default: fail(.permissionDenied, token: token)
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        activeToken = nil
        takingPhoto = false
        lastReadyAt = nil
        analysisQueue.async { [weak self] in
            self?.analysisToken = nil
            self?.evaluator.reset()
            self?.regionTracker.reset()
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capture() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let token = activeToken, !takingPhoto,
              let lastReadyAt, CACurrentMediaTime() - lastReadyAt < 0.5 else { return }
        takingPhoto = true
        let capturedAt = Date()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                DispatchQueue.main.async { [weak self] in self?.fail(.interrupted, token: token) }
                return
            }
            guard let connection = self.photoOutput.connection(with: .video) else {
                DispatchQueue.main.async { [weak self] in self?.fail(.configurationFailed, token: token) }
                return
            }
            self.setPortrait(connection, mirrored: false)
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off
            let delegate = PhotoDelegate { [weak self] data in
                guard let self else { return }
                self.sessionQueue.async {
                    self.photoDelegates.removeValue(forKey: settings.uniqueID)
                    let result = data.flatMap {
                        PhotoProcessor.process($0, configuration: self.configuration, capturedAt: capturedAt)
                    }
                    DispatchQueue.main.async {
                        guard self.activeToken == token else { return }
                        self.takingPhoto = false
                        if let result {
                            self.stop()
                            self.onPhoto?(result)
                        } else { self.fail(.photoFailed, token: token) }
                    }
                }
            }
            self.photoDelegates[settings.uniqueID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func activate(_ token: UUID) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured { try self.configure() }
                self.analysisQueue.async {
                    self.evaluator.reset()
                    self.regionTracker.reset()
                    self.lastAnalysis = -.infinity
                    self.analysisToken = token
                }
                self.session.startRunning()
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.fail(error as? SkinCaptureError ?? .configurationFailed, token: token)
                }
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw SkinCaptureError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 設定失敗後可重試，避免殘留半完成的輸入與輸出。
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw SkinCaptureError.configurationFailed }
        session.addInput(input)
        guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            throw SkinCaptureError.configurationFailed
        }
        session.addOutput(photoOutput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video) { setPortrait(connection, mirrored: false) }
        if let connection = photoOutput.connection(with: .video) { setPortrait(connection, mirrored: false) }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        configured = true
    }

    private func setPortrait(_ connection: AVCaptureConnection, mirrored: Bool) {
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    private func fail(_ error: SkinCaptureError, token: UUID) {
        guard activeToken == token else { return }
        stop()
        onError?(error)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let token = analysisToken,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite, timestamp - lastAnalysis >= 0.12 else { return }
        lastAnalysis = timestamp
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        do {
            // 影像輸出已由 AVCaptureConnection 旋轉成直立，因此不再旋轉一次。
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            // UI 保留可用的低信心觀測；姿態可靠性仍以 0.7 限制快門。
            let observations = (request.results ?? []).filter { $0.confidence >= 0.3 }
            var faces = observations.map {
                FaceMeasurement(bounds: $0.boundingBox, yaw: $0.yaw?.doubleValue,
                                roll: $0.roll?.doubleValue, pitch: $0.pitch?.doubleValue,
                                brightness: BrightnessAnalyzer.meanLuma(in: buffer, faceBounds: $0.boundingBox),
                                poseReliable: $0.confidence >= 0.7)
            }
            if observations.count == 1, let face = observations.first, face.confidence >= 0.7 {
                regionTracker.confirm(face, at: timestamp)
            } else if observations.count > 1 {
                regionTracker.reset()
            } else if observations.isEmpty, let box = regionTracker.track(in: buffer, at: timestamp) {
                faces = [FaceMeasurement(bounds: box, yaw: nil, roll: nil, pitch: nil,
                                         brightness: BrightnessAnalyzer.meanLuma(in: buffer, faceBounds: box),
                                         poseReliable: false)]
            }
            let imageSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
            let evaluation = evaluator.evaluate(faces, at: timestamp, sourceImageSize: imageSize)
            let deliveredAt = CACurrentMediaTime()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeToken == token, !self.takingPhoto else { return }
                // 主執行緒若阻塞，排隊的舊分析結果不能啟動倒數或快門。
                guard CACurrentMediaTime() - deliveredAt < 0.5 else {
                    self.lastReadyAt = nil
                    self.onGuidance?(GuidanceEvaluation(guidance: .holdStill, progress: 0))
                    return
                }
                self.lastReadyAt = evaluation.canCapture ? deliveredAt : nil
                self.onGuidance?(evaluation)
            }
        } catch {
            analysisToken = nil
            DispatchQueue.main.async { [weak self] in self?.fail(.analysisFailed, token: token) }
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var data: Data?
    private let completion: (Data?) -> Void
    init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        data = error == nil ? photo.fileDataRepresentation() : nil
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        completion(error == nil ? data : nil)
    }
}
#endif
