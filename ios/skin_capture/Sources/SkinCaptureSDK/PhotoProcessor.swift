#if canImport(UIKit)
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoProcessor {
    /// 方向直接烘焙到像素；相機已指定不鏡像，這裡不再翻轉左右。
    static func process(_ data: Data, configuration: CaptureConfiguration,
                        capturedAt: Date = Date()) -> SkinCaptureResult? {
        guard configuration.isValid,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let longest = max(width, height)
        let limit = min(configuration.maximumImageDimension ?? longest, longest)
        // ImageIO 直接套用 EXIF 方向並縮圖，避免 UIImage 尺寸與旋轉方向不一致。
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        // 不沿用相機原始 EXIF/GPS；僅輸出影像與正向標記。
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: configuration.jpegQuality,
            kCGImagePropertyOrientation: 1
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return SkinCaptureResult(jpegData: output as Data, width: cgImage.width, height: cgImage.height,
                                 capturedAt: capturedAt)
    }
}
#endif
