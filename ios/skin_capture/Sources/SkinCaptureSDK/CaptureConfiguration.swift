import Foundation

/// 拍攝門檻為經驗值，應依目標手機與實際拍攝情境校正。
public struct CaptureConfiguration: Equatable {
    /// 偵測臉框在預覽中的高度占橢圓引導框高度的比例。
    public var minimumFaceHeight: Double
    public var maximumFaceHeight: Double
    public var centerTolerance: Double
    public var maximumAngle: Double
    public var minimumBrightness: Double
    public var maximumBrightness: Double
    public var stableDuration: TimeInterval
    public var countdownDuration: TimeInterval
    /// nil 表示保留相機解析度；設定數值時只縮小，不放大。
    public var maximumImageDimension: Int?
    public var jpegQuality: Double

    public init(
        minimumFaceHeight: Double = 0.55,
        maximumFaceHeight: Double = 0.80,
        centerTolerance: Double = 0.16,
        maximumAngle: Double = 0.30,
        minimumBrightness: Double = 50.0 / 255.0,
        maximumBrightness: Double = 170.0 / 255.0,
        stableDuration: TimeInterval = 0.6,
        countdownDuration: TimeInterval = 1.0,
        maximumImageDimension: Int? = nil,
        jpegQuality: Double = 0.9
    ) {
        self.minimumFaceHeight = minimumFaceHeight
        self.maximumFaceHeight = maximumFaceHeight
        self.centerTolerance = centerTolerance
        self.maximumAngle = maximumAngle
        self.minimumBrightness = minimumBrightness
        self.maximumBrightness = maximumBrightness
        self.stableDuration = stableDuration
        self.countdownDuration = countdownDuration
        self.maximumImageDimension = maximumImageDimension
        self.jpegQuality = jpegQuality
    }

    public var isValid: Bool {
        minimumFaceHeight.isFinite && maximumFaceHeight.isFinite &&
        (0.1...0.9).contains(minimumFaceHeight) &&
        maximumFaceHeight > minimumFaceHeight && maximumFaceHeight <= 0.95 &&
        centerTolerance.isFinite && (0.01...0.25).contains(centerTolerance) &&
        maximumAngle.isFinite && (0.05...0.6).contains(maximumAngle) &&
        minimumBrightness.isFinite && maximumBrightness.isFinite &&
        (0...1).contains(minimumBrightness) &&
        maximumBrightness > minimumBrightness && maximumBrightness <= 1 &&
        stableDuration.isFinite && (0.2...5).contains(stableDuration) &&
        countdownDuration.isFinite && (1...5).contains(countdownDuration) &&
        jpegQuality.isFinite && (0.5...1).contains(jpegQuality) &&
        (maximumImageDimension == nil || (640...8192).contains(maximumImageDimension!))
    }
}

public enum CaptureGuidance: String, Equatable {
    case noFace, multipleFaces, moveCloser, moveAway, centerFace
    case faceForward, moreLight, lessLight, holdStill, ready

    public var message: String {
        switch self {
        case .noFace: return "請將臉部放入框內"
        case .multipleFaces: return "畫面中請只保留一張臉"
        case .moveCloser: return "請稍微靠近相機"
        case .moveAway: return "請稍微遠離相機"
        case .centerFace: return "請將臉部移到畫面中央"
        case .faceForward: return "請正面面向相機，保持頭部端正"
        case .moreLight: return "光線不足，請移到明亮且均勻的光源前"
        case .lessLight: return "光線太強，請避開直射光"
        case .holdStill: return "請保持不動"
        case .ready: return "準備完成，可以拍照"
        }
    }
}

public enum SkinCaptureError: Error, LocalizedError, Equatable {
    case invalidConfiguration, permissionDenied, cameraUnavailable
    case configurationFailed, interrupted, analysisFailed, photoFailed
    case missingCameraUsageDescription

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "拍攝引導設定不合法"
        case .permissionDenied: return "請到設定允許此 App 使用相機"
        case .cameraUnavailable: return "此裝置無可用的前置相機，請使用實體 iPhone"
        case .configurationFailed: return "無法啟動相機"
        case .interrupted: return "相機暫時無法使用，請稍後重試"
        case .analysisFailed: return "無法辨識畫面，請重新啟動拍攝"
        case .photoFailed: return "拍照失敗，請重試"
        case .missingCameraUsageDescription: return "App 缺少 NSCameraUsageDescription 相機用途說明"
        }
    }
}
