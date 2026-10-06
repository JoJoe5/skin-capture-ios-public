#if canImport(UIKit)
import UIKit
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import SkinCaptureSDK

final class PhotoProcessorTests: XCTestCase {
    func testJPEGIsUprightAndResizedWithoutUpscaling() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 1200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 400, y: 0, width: 400, height: 1200))
        }
        let input = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let result = try XCTUnwrap(PhotoProcessor.process(input, configuration: .init(maximumImageDimension: 640)))
        XCTAssertEqual(Double(result.width), 427, accuracy: 1)
        XCTAssertEqual(result.height, 640)
        XCTAssertEqual(result.mimeType, "image/jpeg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result.jpegData as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 1)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        let unscaled = try XCTUnwrap(PhotoProcessor.process(input, configuration: .init(maximumImageDimension: 2048)))
        XCTAssertEqual(unscaled.width, 800)
        XCTAssertEqual(unscaled.height, 1200)
        let rotatedData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(rotatedData,
                                            UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage),
                                  [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let rotated = try XCTUnwrap(PhotoProcessor.process(rotatedData as Data, configuration: .init()))
        XCTAssertEqual(rotated.width, 1200)
        XCTAssertEqual(rotated.height, 800)
    }

    func testInvalidDataDoesNotReturnAPhoto() {
        XCTAssertNil(PhotoProcessor.process(Data([0, 1, 2]), configuration: .init()))
    }
}
#endif
