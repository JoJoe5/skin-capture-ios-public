import CoreGraphics
import XCTest
@testable import SkinCaptureSDK

final class CaptureTargetPoseTests: XCTestCase {
    private func face(yaw: Double?, roll: Double? = 0, pitch: Double? = 0,
                      poseReliable: Bool = true) -> FaceMeasurement {
        FaceMeasurement(bounds: CGRect(x: 0.25, y: 0.23875, width: 0.5, height: 0.5625),
                        yaw: yaw, roll: roll, pitch: pitch, brightness: 0.45,
                        poseReliable: poseReliable)
    }

    func testSignedTargetsRequireCorrectSideAndContinuousStability() {
        for target in [-45.0, 45.0] {
            let config = CaptureConfiguration(maximumAngle: 10 * .pi / 180, targetYawDegrees: target)
            var evaluator = GuidanceEvaluator(configuration: config)
            let yaw = target * .pi / 180
            for wrong in [0.0, -yaw, yaw + 11 * .pi / 180, yaw - 11 * .pi / 180] {
                let result = evaluator.evaluate([face(yaw: wrong)], at: 0)
                XCTAssertEqual(result.guidance, .faceForward)
                XCTAssertEqual(result.quality.angle, .failed)
                XCTAssertFalse(result.canCapture)
            }
            for time in [0.0, 0.2, 0.4] {
                let result = evaluator.evaluate([face(yaw: yaw)], at: time)
                XCTAssertEqual(result.quality.angle, .passed)
                XCTAssertFalse(result.canCapture)
                XCTAssertEqual(result.yawDegrees ?? 0, target, accuracy: 0.000001)
            }
            XCTAssertTrue(evaluator.evaluate([face(yaw: yaw)], at: 0.6).canCapture)
            let paused = evaluator.evaluate([face(yaw: 0)], at: 0.8)
            XCTAssertFalse(paused.canCapture)
            XCTAssertEqual(paused.quality.angle, .failed)
            XCTAssertTrue(evaluator.evaluate([face(yaw: yaw)], at: 1.0).canCapture)
        }
    }

    func testTargetToleranceIncludesBothBoundariesButStillRequiresUprightPose() {
        for target in [-45.0, 45.0] {
            let config = CaptureConfiguration(maximumAngle: 10 * .pi / 180, targetYawDegrees: target)
            let yaw = target * .pi / 180
            for degrees in [target - 10, target + 10] {
                var evaluator = GuidanceEvaluator(configuration: config)
                let measurement = face(yaw: degrees * .pi / 180)
                for time in [0.0, 0.2, 0.4, 0.6] {
                    let result = evaluator.evaluate([measurement], at: time)
                    XCTAssertEqual(result.quality.angle, .passed)
                    XCTAssertEqual(result.canCapture, time >= 0.6)
                }
            }
            for invalid in [face(yaw: yaw, roll: 0.3), face(yaw: yaw, pitch: -0.3),
                            face(yaw: nil), face(yaw: .nan), face(yaw: .infinity),
                            face(yaw: yaw, pitch: nil), face(yaw: yaw, poseReliable: false)] {
                var evaluator = GuidanceEvaluator(configuration: config)
                let result = evaluator.evaluate([invalid], at: 0)
                XCTAssertFalse(result.canCapture)
                XCTAssertEqual(result.quality.angle, .failed)
            }
            var evaluator = GuidanceEvaluator(configuration: config)
            let estimate = evaluator.evaluate([face(yaw: yaw, poseReliable: false)], at: 0)
            XCTAssertEqual(estimate.yawDegrees ?? 0, target, accuracy: 0.000001)
            XCTAssertFalse(estimate.poseReliable)
            XCTAssertFalse(estimate.canCapture)
            XCTAssertNil(evaluator.evaluate([face(yaw: nil, poseReliable: false)], at: 0.1).yawDegrees)
            XCTAssertNil(evaluator.evaluate([face(yaw: yaw), face(yaw: yaw)], at: 0).yawDegrees)
        }
    }

    func testTargetConfigurationRejectsInvalidValuesAndAcceptsLimits() {
        XCTAssertEqual(CaptureConfiguration().targetYawDegrees, 0)
        for target in [-60.0, 0.0, 60.0] {
            XCTAssertTrue(CaptureConfiguration(targetYawDegrees: target).isValid)
        }
        for target in [-61.0, 61.0, .nan, .infinity] {
            let config = CaptureConfiguration(targetYawDegrees: target)
            XCTAssertFalse(config.isValid)
            var evaluator = GuidanceEvaluator(configuration: config)
            XCTAssertFalse(evaluator.evaluate([face(yaw: 0)], at: 0).canCapture)
        }
    }
}
