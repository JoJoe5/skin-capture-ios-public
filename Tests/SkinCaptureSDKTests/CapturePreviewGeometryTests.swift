import CoreGraphics
import XCTest
@testable import SkinCaptureSDK

final class CapturePreviewGeometryTests: XCTestCase {
    func testFixedGuidePreservesCameraAspectRatioAndCenter() {
        let viewport = CGRect(x: 0, y: 0, width: 350, height: 437.5)
        for size in [CGSize(width: 3, height: 4), CGSize(width: 9, height: 16)] {
            let image = CapturePreviewGeometry.imageRect(in: viewport, imageSize: size)
            XCTAssertEqual(image.height * 0.75, viewport.height, accuracy: 0.001)
            XCTAssertEqual(image.minX + image.width * 0.5, viewport.midX, accuracy: 0.001)
            XCTAssertEqual(image.minY + image.height * 0.48, viewport.midY, accuracy: 0.001)
            XCTAssertEqual(image.width / image.height, size.width / size.height, accuracy: 0.001)
        }
    }

    func testChangingThresholdsKeepsPreviewFixedAndOnlyChangesAcceptedFaceSizes() {
        let viewport = CGRect(x: 0, y: 0, width: 350, height: 437.5)
        let image = CapturePreviewGeometry.imageRect(in: viewport, imageSize: CGSize(width: 3, height: 4))
        for configuration in [CaptureConfiguration(), .init(minimumFaceHeight: 0.5, maximumFaceHeight: 0.7)] {
            let range = CapturePreviewGeometry.faceHeightRange(configuration: configuration)
            XCTAssertEqual(image.height * range.lowerBound, viewport.height * configuration.minimumFaceHeight, accuracy: 0.001)
            XCTAssertEqual(image.height * range.upperBound, viewport.height * configuration.maximumFaceHeight, accuracy: 0.001)
            XCTAssertEqual(image.height, viewport.height / 0.75, accuracy: 0.001)
        }
        XCTAssertEqual(CapturePreviewGeometry.imageRect(in: viewport, imageSize: .zero), viewport)
    }

    func testVisibleGuideHeightMatchesBadgesGuidanceAndShutterAcrossPhoneSizes() {
        for viewport in [CGRect(x: 0, y: 0, width: 270, height: 337.5),
                         CGRect(x: 0, y: 0, width: 350, height: 437.5),
                         CGRect(x: 0, y: 0, width: 398, height: 497.5)] {
            for size in [CGSize(width: 1080, height: 1440), CGSize(width: 1080, height: 1920)] {
                let image = CapturePreviewGeometry.imageRect(in: viewport, imageSize: size)
                for fraction in [0.59, 0.60, 0.65, 0.70, 0.75, 0.80, 0.81] {
                    let height = fraction * 0.75
                    let bounds = CGRect(x: 0.25, y: 0.52 - height / 2, width: 0.5, height: height)
                    XCTAssertEqual(bounds.height * image.height / viewport.height, fraction, accuracy: 0.0001)
                    let face = FaceMeasurement(bounds: bounds, yaw: 0, roll: 0, pitch: 0, brightness: 0.45)
                    var evaluator = GuidanceEvaluator(configuration: .init())
                    let first = evaluator.evaluate([face], at: 0)
                    let passes = (0.60...0.80).contains(fraction)
                    XCTAssertEqual(first.quality.size, passes ? .passed : .failed)
                    XCTAssertEqual(first.guidance, fraction < 0.60 ? .moveCloser : fraction > 0.80 ? .moveAway : .holdStill)
                    for time in [0.2, 0.4] { _ = evaluator.evaluate([face], at: time) }
                    XCTAssertEqual(evaluator.evaluate([face], at: 0.6).canCapture, passes)
                }
            }
        }
    }
}
