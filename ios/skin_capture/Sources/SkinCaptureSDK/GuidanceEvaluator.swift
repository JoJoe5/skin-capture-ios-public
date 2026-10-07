import Foundation
import CoreGraphics

struct FaceMeasurement {
    let bounds: CGRect
    let yaw: Double?
    let roll: Double?
    let pitch: Double?
    let brightness: Double
    let poseReliable: Bool

    init(bounds: CGRect, yaw: Double?, roll: Double?, pitch: Double?, brightness: Double, poseReliable: Bool = true) {
        self.bounds = bounds
        self.yaw = yaw
        self.roll = roll
        self.pitch = pitch
        self.brightness = brightness
        self.poseReliable = poseReliable
    }
}

struct GuidanceEvaluation {
    let guidance: CaptureGuidance
    let progress: Double
    let canCapture: Bool
    let quality: CaptureQuality
    let blockingGuidance: CaptureGuidance?
    let sourceImageSize: CGSize?
    let yawDegrees: Double?

    init(guidance: CaptureGuidance, progress: Double, canCapture: Bool? = nil,
         quality: CaptureQuality = .unknown, blockingGuidance: CaptureGuidance? = nil,
         sourceImageSize: CGSize? = nil, yawDegrees: Double? = nil) {
        self.guidance = guidance
        self.progress = progress
        self.canCapture = canCapture ?? (guidance == .ready)
        self.quality = quality
        self.blockingGuidance = blockingGuidance
        self.sourceImageSize = sourceImageSize
        self.yawDegrees = yawDegrees
    }
}

/// 純函式輸入與狀態計時，不依賴相機，可測試邊界與掉幀情況。
struct GuidanceEvaluator {
    let configuration: CaptureConfiguration
    private var stableSince: TimeInterval?
    private var previousTimestamp: TimeInterval?
    private var previousBounds: CGRect?
    private var invalidSince: TimeInterval?
    private var lastProgress: Double = 0

    init(configuration: CaptureConfiguration) {
        self.configuration = configuration
    }

    mutating func reset() {
        stableSince = nil
        previousTimestamp = nil
        previousBounds = nil
        invalidSince = nil
        lastProgress = 0
    }

    mutating func evaluate(_ faces: [FaceMeasurement], at timestamp: TimeInterval,
                           sourceImageSize: CGSize? = nil) -> GuidanceEvaluation {
        let quality = timestamp.isFinite ? CaptureQuality.measure(faces, configuration: configuration) : .unknown
        let result = evaluateGuidance(faces, at: timestamp)
        let yawDegrees: Double? = timestamp.isFinite && faces.count == 1 && faces[0].poseReliable
            ? faces[0].yaw.flatMap { $0.isFinite ? $0 * 180 / .pi : nil } : nil
        return GuidanceEvaluation(guidance: result.guidance, progress: result.progress,
                                  canCapture: result.canCapture, quality: quality,
                                  blockingGuidance: result.blockingGuidance, sourceImageSize: sourceImageSize,
                                  yawDegrees: yawDegrees)
    }

    private mutating func evaluateGuidance(_ faces: [FaceMeasurement], at timestamp: TimeInterval) -> GuidanceEvaluation {
        guard configuration.isValid, timestamp.isFinite else { return reject(.noFace) }
        // 掉幀或時鐘倒退不能沿用先前的穩定與容錯時間。
        if let previousTimestamp,
           timestamp <= previousTimestamp || timestamp - previousTimestamp > 0.5 {
            reset()
        }
        if let invalidSince, timestamp - invalidSince >= 0.35 { reset() }
        previousTimestamp = timestamp
        guard faces.count == 1 else { return reject(faces.isEmpty ? .noFace : .multipleFaces) }
        let face = faces[0]
        let box = face.bounds
        guard !box.isNull, !box.isEmpty,
              [box.minX, box.minY, box.maxX, box.maxY].allSatisfy({ $0.isFinite }),
              box.minX >= 0, box.minY >= 0, box.maxX <= 1, box.maxY <= 1 else {
            return reject(.centerFace)
        }
        // 追蹤或低信心結果只供各欄顯示；必須重新取得可靠姿態才能拍照。
        guard face.poseReliable else { return reject(.faceForward) }
        let heightRange = CapturePreviewGeometry.faceHeightRange(configuration: configuration)
        if box.height < heightRange.lowerBound { return temporarilyReject(.moveCloser, at: timestamp) }
        if box.height > heightRange.upperBound { return temporarilyReject(.moveAway, at: timestamp) }
        if abs(box.midX - 0.5) > configuration.centerTolerance ||
            abs(box.midY - 0.52) > configuration.centerTolerance { return temporarilyReject(.centerFace, at: timestamp) }
        guard let yaw = face.yaw, let roll = face.roll, let pitch = face.pitch,
              [yaw, roll, pitch].allSatisfy({ $0.isFinite }) else {
            return reject(.faceForward)
        }
        if !configuration.acceptsPose(yaw: yaw, roll: roll, pitch: pitch) {
            return temporarilyReject(.faceForward, at: timestamp)
        }
        guard face.brightness.isFinite else { return reject(.moreLight) }
        if face.brightness < configuration.minimumBrightness { return temporarilyReject(.moreLight, at: timestamp) }
        if face.brightness > configuration.maximumBrightness { return temporarilyReject(.lessLight, at: timestamp) }
        if let previousBounds,
           abs(box.midX - previousBounds.midX) > 0.05 ||
            abs(box.midY - previousBounds.midY) > 0.05 ||
            abs(box.width - previousBounds.width) > 0.05 ||
            abs(box.height - previousBounds.height) > 0.05 {
            return temporarilyReject(.holdStill, at: timestamp)
        }
        if let invalidSince {
            // 不符合條件的時間不計入穩定時間，恢復後延續已累積的進度。
            if let stableSince { self.stableSince = stableSince + timestamp - invalidSince }
            self.invalidSince = nil
        }
        previousBounds = box
        if stableSince == nil { stableSince = timestamp }
        let progress = min(1, max(0, (timestamp - (stableSince ?? timestamp)) / configuration.stableDuration))
        lastProgress = progress
        return GuidanceEvaluation(guidance: progress >= 1 ? .ready : .holdStill, progress: progress)
    }

    private mutating func temporarilyReject(_ guidance: CaptureGuidance, at timestamp: TimeInterval) -> GuidanceEvaluation {
        guard stableSince != nil else { return reject(guidance) }
        if invalidSince == nil { invalidSince = timestamp }
        guard timestamp - (invalidSince ?? timestamp) < 0.35 else { return reject(guidance) }
        // 保留倒數狀態，但快門與 UI 均不得將暫停中的畫面視為可拍攝。
        return GuidanceEvaluation(guidance: lastProgress >= 1 ? .ready : .holdStill,
                                  progress: lastProgress, canCapture: false, blockingGuidance: guidance)
    }

    private mutating func reject(_ guidance: CaptureGuidance) -> GuidanceEvaluation {
        reset()
        return GuidanceEvaluation(guidance: guidance, progress: 0)
    }
}
