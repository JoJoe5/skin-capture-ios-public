#if canImport(UIKit)
import CoreVideo
import Foundation

enum BrightnessAnalyzer {
    /// 資料輸出使用完整範圍 YUV；Vision 座標左下為原點，影像列左上為原點。
    /// 取臉框內縮區域的 Y 平均值，避開背景；這是經驗亮度指標，不是環境照度。
    static func meanLuma(in buffer: CVPixelBuffer, faceBounds: CGRect) -> Double {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return .nan }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return .nan }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard !faceBounds.isNull, !faceBounds.isEmpty,
              [faceBounds.minX, faceBounds.minY, faceBounds.maxX, faceBounds.maxY].allSatisfy({ $0.isFinite }) else { return .nan }
        let box = faceBounds.insetBy(dx: faceBounds.width * 0.12, dy: faceBounds.height * 0.12)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !box.isNull, !box.isEmpty else { return .nan }
        let minX = max(0, min(width - 1, Int(box.minX * Double(width))))
        let maxX = max(minX, min(width - 1, Int(box.maxX * Double(width))))
        let minY = max(0, min(height - 1, Int((1 - box.maxY) * Double(height))))
        let maxY = max(minY, min(height - 1, Int((1 - box.minY) * Double(height))))
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var sum: Double = 0
        var count = 0
        for y in stride(from: minY, through: maxY, by: 4) {
            for x in stride(from: minX, through: maxX, by: 4) {
                sum += Double(pixels[y * bytesPerRow + x])
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) / 255 : .nan
    }
}
#endif
