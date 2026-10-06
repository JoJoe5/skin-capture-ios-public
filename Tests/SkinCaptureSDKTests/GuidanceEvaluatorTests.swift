import Foundation
import CoreGraphics
import XCTest
@testable import SkinCaptureSDK

final class GuidanceEvaluatorTests: XCTestCase {
    private func face(bounds: CGRect = CGRect(x: 0.25, y: 0.23875, width: 0.5, height: 0.5625),
                      yaw: Double? = 0, roll: Double? = 0, pitch: Double? = 0,
                      brightness: Double = 0.45) -> FaceMeasurement {
        FaceMeasurement(bounds: bounds, yaw: yaw, roll: roll, pitch: pitch, brightness: brightness)
    }

    func testReadyRequiresContinuousStableFrames() {
        var evaluator = GuidanceEvaluator(configuration: .init(stableDuration: 1))
        XCTAssertEqual(evaluator.evaluate([face()], at: 0).guidance, .holdStill)
        for time in stride(from: 0.2, through: 0.8, by: 0.2) {
            XCTAssertEqual(evaluator.evaluate([face()], at: time).guidance, .holdStill)
        }
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.0).guidance, .ready)
    }

    func testNoFaceAndMultipleFacesResetStability() {
        var evaluator = GuidanceEvaluator(configuration: .init())
        _ = evaluator.evaluate([face()], at: 0)
        XCTAssertEqual(evaluator.evaluate([], at: 0.4).guidance, .noFace)
        XCTAssertEqual(evaluator.evaluate([face(), face()], at: 0.5).guidance, .multipleFaces)
        XCTAssertEqual(evaluator.evaluate([face()], at: 0.6).progress, 0)
    }

    func testDistanceCenterAndPoseProduceUsefulGuidance() {
        var evaluator = GuidanceEvaluator(configuration: .init())
        XCTAssertEqual(evaluator.evaluate([face(bounds: CGRect(x: 0.4, y: 0.35, width: 0.2, height: 0.3))], at: 0).guidance, .moveCloser)
        XCTAssertEqual(evaluator.evaluate([face(bounds: CGRect(x: 0.25, y: 0.05, width: 0.5, height: 0.9))], at: 0).guidance, .moveAway)
        XCTAssertEqual(evaluator.evaluate([face(bounds: CGRect(x: 0, y: 0.23875, width: 0.5, height: 0.5625))], at: 0).guidance, .centerFace)
        for tilted in [face(yaw: 0.4), face(roll: 0.4), face(pitch: 0.4), face(pitch: nil)] {
            XCTAssertEqual(evaluator.evaluate([tilted], at: 0).guidance, .faceForward)
        }
    }

    func testBrightnessBoundariesAndInvalidMeasurements() {
        let config = CaptureConfiguration()
        var evaluator = GuidanceEvaluator(configuration: config)
        XCTAssertEqual(evaluator.evaluate([face(brightness: config.minimumBrightness - 0.001)], at: 0).guidance, .moreLight)
        XCTAssertEqual(evaluator.evaluate([face(brightness: config.maximumBrightness + 0.001)], at: 0).guidance, .lessLight)
        XCTAssertEqual(evaluator.evaluate([face(brightness: config.minimumBrightness)], at: 0).guidance, .holdStill)
        XCTAssertEqual(evaluator.evaluate([face(brightness: config.maximumBrightness)], at: 0.2).guidance, .holdStill)
        XCTAssertEqual(evaluator.evaluate([face(brightness: .nan)], at: 0.3).guidance, .moreLight)
        XCTAssertEqual(evaluator.evaluate([face(yaw: .nan)], at: 0.4).guidance, .faceForward)
    }

    func testDroppedFramesClockReversalAndMotionResetTimer() {
        var evaluator = GuidanceEvaluator(configuration: .init())
        _ = evaluator.evaluate([face()], at: 0)
        _ = evaluator.evaluate([face()], at: 0.4)
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.5).progress, 0)
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.4).progress, 0)
        _ = evaluator.evaluate([face()], at: 1.6)
        let moving = face(bounds: CGRect(x: 0.31, y: 0.23875, width: 0.5, height: 0.5625))
        XCTAssertFalse(evaluator.evaluate([moving], at: 1.8).canCapture)
        XCTAssertEqual(evaluator.evaluate([moving], at: 2.2).progress, 0)
    }

    func testInvalidConfigurationAndBoundsNeverBecomeReady() {
        XCTAssertFalse(CaptureConfiguration(minimumBrightness: 0.9, maximumBrightness: 0.2).isValid)
        XCTAssertFalse(CaptureConfiguration(stableDuration: .nan).isValid)
        XCTAssertFalse(CaptureConfiguration(countdownDuration: 0).isValid)
        XCTAssertFalse(CaptureConfiguration(jpegQuality: 2).isValid)
        XCTAssertFalse(CaptureConfiguration(maximumImageDimension: 1).isValid)
        var evaluator = GuidanceEvaluator(configuration: .init())
        XCTAssertEqual(evaluator.evaluate([face(bounds: CGRect(x: -0.1, y: 0, width: 0.5, height: 0.6))], at: 0).guidance, .centerFace)
        XCTAssertEqual(evaluator.evaluate([face()], at: .nan).guidance, .noFace)
    }

    private func readyEvaluator() -> GuidanceEvaluator {
        var evaluator = GuidanceEvaluator(configuration: .init())
        for time in [0.0, 0.2, 0.4, 0.6] { _ = evaluator.evaluate([face()], at: time) }
        return evaluator
    }

    func testSmallHandMovementDoesNotRestartCountdown() {
        var evaluator = readyEvaluator()
        let result = evaluator.evaluate([face(bounds: CGRect(x: 0.29, y: 0.23875, width: 0.5, height: 0.5625))], at: 0.8)
        XCTAssertEqual(result.guidance, .ready)
        XCTAssertTrue(result.canCapture)
    }

    func testBriefPoseBrightnessDistanceAndCenterFailuresPauseThenResume() {
        let failures = [face(yaw: 0.31), face(brightness: 0.7),
                        face(bounds: CGRect(x: 0.25, y: 0.3175, width: 0.5, height: 0.405)),
                        face(bounds: CGRect(x: 0, y: 0.23875, width: 0.5, height: 0.5625))]
        for failure in failures {
            var evaluator = readyEvaluator()
            let paused = evaluator.evaluate([failure], at: 0.8)
            XCTAssertEqual(paused.guidance, .ready)
            XCTAssertFalse(paused.canCapture)
            let resumed = evaluator.evaluate([face()], at: 1.0)
            XCTAssertEqual(resumed.guidance, .ready)
            XCTAssertTrue(resumed.canCapture)
        }
    }

    func testPersistentOrChangingFailuresAndLateRecoveryResetCountdown() {
        var evaluator = readyEvaluator()
        _ = evaluator.evaluate([face(yaw: 0.4)], at: 0.8)
        _ = evaluator.evaluate([face(brightness: 0.9)], at: 1.0)
        let failed = evaluator.evaluate([face(yaw: 0.4)], at: 1.16)
        XCTAssertEqual(failed.guidance, .faceForward)
        XCTAssertEqual(failed.progress, 0)
        XCTAssertFalse(failed.canCapture)
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.3).progress, 0)

        evaluator = readyEvaluator()
        _ = evaluator.evaluate([face(yaw: 0.4)], at: 0.8)
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.16).progress, 0)
    }

    func testInvalidTimeDoesNotCountTowardStability() {
        var evaluator = GuidanceEvaluator(configuration: .init(stableDuration: 1))
        _ = evaluator.evaluate([face()], at: 0)
        _ = evaluator.evaluate([face()], at: 0.2)
        _ = evaluator.evaluate([face(yaw: 0.4)], at: 0.4)
        XCTAssertEqual(evaluator.evaluate([face()], at: 0.6).progress, 0.4, accuracy: 0.0001)
        _ = evaluator.evaluate([face()], at: 0.8)
        _ = evaluator.evaluate([face()], at: 1.0)
        XCTAssertTrue(evaluator.evaluate([face()], at: 1.21).canCapture)
    }

    func testMissingMultipleOrInvalidFacesImmediatelyCancelReadyState() {
        for faces in [[], [face(), face()], [face(yaw: .nan)],
                      [face(bounds: CGRect(x: -0.1, y: 0, width: 0.5, height: 0.6))]] {
            var evaluator = readyEvaluator()
            XCTAssertFalse(evaluator.evaluate(faces, at: 0.8).canCapture)
            XCTAssertEqual(evaluator.evaluate([face()], at: 1.0).progress, 0)
        }
    }

    func testDroppedFramesDuringPauseRequireNewStableFrames() {
        var evaluator = readyEvaluator()
        _ = evaluator.evaluate([face(yaw: 0.4)], at: 0.8)
        XCTAssertEqual(evaluator.evaluate([face()], at: 1.4).progress, 0)
    }

    func testHeightMotionWithinAcceptedRangePausesShutter() {
        var evaluator = GuidanceEvaluator(configuration: .init())
        let taller = face(bounds: CGRect(x: 0.25, y: 0.22, width: 0.5, height: 0.80 * 0.75))
        // 先以 60% 穩定，再移到仍在合格範圍內的 80%；尺寸合格不代表已停止移動。
        let shorter = face(bounds: CGRect(x: 0.25, y: 0.295, width: 0.5, height: 0.60 * 0.75))
        for time in [0.0, 0.2, 0.4, 0.6] { _ = evaluator.evaluate([shorter], at: time) }
        let result = evaluator.evaluate([taller], at: 0.8)
        XCTAssertEqual(result.quality.size, .passed)
        XCTAssertEqual(result.blockingGuidance, .holdStill)
        XCTAssertFalse(result.canCapture)
    }

    func testOnlyFiftyFiveToEightyPercentGuideHeightsCanBecomeReady() {
        for height in [0.54, 0.55, 0.59, 0.60, 0.65, 0.70, 0.75, 0.80, 0.81] {
            var evaluator = GuidanceEvaluator(configuration: .init())
            let measurement = face(bounds: CGRect(x: 0.25, y: 0.52 - height * 0.75 / 2, width: 0.5, height: height * 0.75))
            let first = evaluator.evaluate([measurement], at: 0)
            let expected: CaptureGuidance = height < 0.55 ? .moveCloser : height > 0.80 ? .moveAway : .holdStill
            XCTAssertEqual(first.guidance, expected, "引導框高度占比：\(height)")
            XCTAssertEqual(first.quality.size, (0.55...0.80).contains(height) ? .passed : .failed)
            XCTAssertEqual(first.quality.lighting, .passed)
            XCTAssertEqual(first.quality.angle, .passed)
            _ = evaluator.evaluate([measurement], at: 0.2)
            _ = evaluator.evaluate([measurement], at: 0.4)
            XCTAssertEqual(evaluator.evaluate([measurement], at: 0.6).canCapture, (0.55...0.80).contains(height))
        }
    }

}
