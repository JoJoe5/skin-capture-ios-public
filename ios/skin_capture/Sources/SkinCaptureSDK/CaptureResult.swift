#if canImport(UIKit)
import UIKit

public struct SkinCaptureResult {
    public let jpegData: Data
    public let width: Int
    public let height: Int
    public let capturedAt: Date
    public var mimeType: String { "image/jpeg" }

    init(jpegData: Data, width: Int, height: Int, capturedAt: Date = Date()) {
        self.jpegData = jpegData
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }
}

public struct CaptureAppearance {
    public var accentColor: UIColor
    public var title: String
    public var confirmText: String
    public var retakeText: String
    /// 以 CaptureGuidance.rawValue 為鍵覆寫提示文字。
    public var guidanceMessages: [String: String]

    public init(
        accentColor: UIColor = UIColor(red: 0.05, green: 0.63, blue: 0.52, alpha: 1),
        title: String = "正臉拍攝",
        confirmText: String = "使用這張照片",
        retakeText: String = "重新拍攝",
        guidanceMessages: [String: String] = [:]
    ) {
        self.accentColor = accentColor
        self.title = title
        self.confirmText = confirmText
        self.retakeText = retakeText
        self.guidanceMessages = guidanceMessages
    }
}
#endif
