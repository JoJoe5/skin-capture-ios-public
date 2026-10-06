import CoreGraphics

enum CapturePreviewGeometry {
    /// 引導框固定顯示完整影像高度的 75%；調整大小門檻不再改變預覽縮放。
    static let guideHeightInImage: CGFloat = 0.75

    static func imageRect(in viewport: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              imageSize.width.isFinite, imageSize.height.isFinite else { return viewport }
        let height = viewport.height / guideHeightInImage
        let width = height * imageSize.width / imageSize.height
        return CGRect(x: viewport.midX - width / 2, y: viewport.midY - height * 0.48,
                      width: width, height: height)
    }

    /// 設定以橢圓框為基準，判定前轉成 Vision 使用的完整影像比例。
    /// 直接比較換算後的邊界，避免除法誤差讓恰好下限或上限 的臉被拒絕。
    static func faceHeightRange(configuration: CaptureConfiguration) -> ClosedRange<CGFloat> {
        let minimum = CGFloat(configuration.minimumFaceHeight) * guideHeightInImage
        let maximum = CGFloat(configuration.maximumFaceHeight) * guideHeightInImage
        return minimum...maximum
    }
}
