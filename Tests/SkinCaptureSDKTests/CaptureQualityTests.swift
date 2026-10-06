import CoreGraphics
import XCTest
@testable import SkinCaptureSDK

final class CaptureQualityTests: XCTestCase {
    private func face(height: Double = 0.75 * 0.75, width: Double = 0.5, centerX: Double = 0.5, centerY: Double = 0.52,
                      yaw: Double? = 0, roll: Double? = 0, pitch: Double? = 0,
                      brightness: Double = 0.45) -> FaceMeasurement {
        FaceMeasurement(bounds: CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height),
                        yaw: yaw, roll: roll, pitch: pitch, brightness: brightness)
    }

    func testThreeDimensionsAreIndependentEvenWhenSizeFailsFirst() {
        let quality = CaptureQuality.measure([face(height: 0.3, yaw: 0.4, brightness: 0.1)], configuration: .init())
        XCTAssertEqual(quality, CaptureQuality(lighting: .failed, angle: .failed, size: .failed))
        let tooFar = CaptureQuality.measure([face(height: 0.3)], configuration: .init())
        XCTAssertEqual(tooFar, CaptureQuality(lighting: .passed, angle: .passed, size: .failed))
    }

    func testNoFaceMultipleFacesAndInvalidBoundsRemainUnknown() {
        for faces in [[], [face(), face()], [face(centerX: -1)]] {
            XCTAssertEqual(CaptureQuality.measure(faces, configuration: .init()), .unknown)
        }
        XCTAssertEqual(CaptureQuality.measure([face()], configuration: .init(maximumBrightness: 0)), .unknown)
    }

    func testAngleIncludesEachPoseAxisAndCenter() {
        for measurement in [face(yaw: 0.4), face(roll: 0.4), face(pitch: 0.4), face(pitch: nil), face(width: 0.3, centerX: 0.25)] {
            let quality = CaptureQuality.measure([measurement], configuration: .init())
            XCTAssertEqual(quality.angle, .failed)
            XCTAssertEqual(quality.lighting, .passed)
            XCTAssertEqual(quality.size, .passed)
        }
    }

    func testBoundariesAreInclusiveAndNonFiniteValuesNeverPass() {
        let configuration = CaptureConfiguration()
        for measurement in [face(height: 0.6 * 0.75, yaw: 0.3, brightness: configuration.minimumBrightness),
                            face(height: 0.8 * 0.75, roll: -0.3, brightness: configuration.maximumBrightness)] {
            XCTAssertEqual(CaptureQuality.measure([measurement], configuration: configuration),
                           CaptureQuality(lighting: .passed, angle: .passed, size: .passed))
        }
        XCTAssertEqual(CaptureQuality.measure([face(brightness: .nan)], configuration: configuration).lighting, .unknown)
        XCTAssertEqual(CaptureQuality.measure([face(yaw: .infinity)], configuration: configuration).angle, .failed)
    }

    func testPausedCountdownDisplaysCurrentFailureInsteadOfPreviousGreenState() {
        var evaluator = GuidanceEvaluator(configuration: .init())
        for timestamp in [0.0, 0.2, 0.4, 0.6] { _ = evaluator.evaluate([face()], at: timestamp) }
        let result = evaluator.evaluate([face(brightness: 0.1)], at: 0.8)
        XCTAssertEqual(result.guidance, .ready)
        XCTAssertFalse(result.canCapture)
        XCTAssertEqual(result.blockingGuidance, .moreLight)
        XCTAssertEqual(result.quality, CaptureQuality(lighting: .failed, angle: .passed, size: .passed))
    }

    func testTrackedRegionMeasuresCurrentLightAndSizeButNeverEnablesShutter() {
        var evaluator = GuidanceEvaluator(configuration: .init())
        for timestamp in [0.0, 0.2, 0.4, 0.6] { _ = evaluator.evaluate([face()], at: timestamp) }
        let tracked = FaceMeasurement(bounds: face().bounds, yaw: 0, roll: 0, pitch: 0,
                                      brightness: 0.45, poseReliable: false)
        let result = evaluator.evaluate([tracked], at: 0.8)
        XCTAssertEqual(result.guidance, .faceForward)
        XCTAssertFalse(result.canCapture)
        XCTAssertEqual(result.quality, CaptureQuality(lighting: .passed, angle: .failed, size: .passed))
        let darker = FaceMeasurement(bounds: face(height: 0.59 * 0.75).bounds, yaw: nil, roll: nil, pitch: nil,
                                     brightness: 0.1, poseReliable: false)
        XCTAssertEqual(evaluator.evaluate([darker], at: 1.0).quality,
                       CaptureQuality(lighting: .failed, angle: .failed, size: .failed))
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.2).progress, 0)
    }

    func testPartiallyVisibleFaceDoesNotEraseValidBrightnessMeasurement() {
        XCTAssertEqual(CaptureQuality.measure([face(centerX: 0)], configuration: .init()),
                       CaptureQuality(lighting: .passed, angle: .failed, size: .failed))
    }

    func testFaceSizeUsesHeightIndependentlyOfWidth() {
        for width in [0.3, 0.5, 0.7] {
            XCTAssertEqual(CaptureQuality.measure([face(height: 0.75 * 0.75, width: width)], configuration: .init()).size, .passed)
            XCTAssertEqual(CaptureQuality.measure([face(height: 0.59 * 0.75, width: width)], configuration: .init()).size, .failed)
        }
    }
}
