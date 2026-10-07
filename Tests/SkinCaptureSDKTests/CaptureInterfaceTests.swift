#if canImport(UIKit)
import UIKit
import XCTest
@testable import SkinCaptureSDK

final class CaptureInterfaceTests: XCTestCase {
    @MainActor
    func testSidePoseHintUsesConfiguredTargetAndCurrentMeasurement() {
        let controller = SkinCaptureViewController(configuration: .init(targetYawDegrees: 45)) { _ in }
        controller.loadViewIfNeeded()
        controller.renderGuidance(GuidanceEvaluation(guidance: .faceForward, progress: 0, yawDegrees: 12, poseReliable: true))
        XCTAssertEqual(controller.guidanceLabel.text, "請調整臉部角度")
        XCTAssertEqual(controller.detailLabel.text, "目前 +12°；目標 +45°，保持頭部端正")
        controller.renderGuidance(GuidanceEvaluation(guidance: .noFace, progress: 0))
        XCTAssertEqual(controller.detailLabel.text, "請將臉部放入框內，目標轉頭 +45°")
    }

    @MainActor
    func testAngleRemainsVisibleDuringOtherGuidanceAndClearsWhenMissing() {
        let controller = SkinCaptureViewController(configuration: .init(targetYawDegrees: 16)) { _ in }
        controller.loadViewIfNeeded()
        for guidance in [CaptureGuidance.moveAway, .moreLight, .holdStill, .ready] {
            controller.renderGuidance(GuidanceEvaluation(guidance: guidance, progress: 0,
                yawDegrees: 12, poseReliable: true))
            XCTAssertEqual(controller.qualityView.angle.accessibilityHint, "目前 +12 度，目標 +16 度")
        }
        controller.renderGuidance(GuidanceEvaluation(guidance: .faceForward, progress: 0,
            yawDegrees: 12, poseReliable: false))
        XCTAssertEqual(controller.guidanceLabel.text, "角度尚待確認")
        XCTAssertEqual(controller.qualityView.angle.accessibilityHint, "目前估計 +12 度，目標 +16 度")
        controller.renderGuidance(GuidanceEvaluation(guidance: .faceForward, progress: 0))
        XCTAssertEqual(controller.guidanceLabel.text, "角度尚未辨識")
        XCTAssertEqual(controller.qualityView.angle.accessibilityHint, "目前角度尚未辨識，目標 +16 度")
    }

    @MainActor
    func testIndicatorsAndOvalDoNotOverlapOnSmallAndLargePhones() {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 390, height: 844), CGSize(width: 430, height: 932)] {
            let controller = SkinCaptureViewController { _ in }
            controller.loadViewIfNeeded()
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: size.height > 700 ? 59 : 20,
                                                               left: 0, bottom: size.height > 700 ? 34 : 0, right: 0)
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.renderGuidance(GuidanceEvaluation(guidance: .moveCloser, progress: 0,
                quality: CaptureQuality(lighting: .passed, angle: .passed, size: .failed),
                yawDegrees: -45, poseReliable: true))
            controller.view.layoutIfNeeded()
            XCTAssertGreaterThan(controller.cameraViewport.frame.width, size.width * 0.7)
            XCTAssertLessThan(controller.qualityView.frame.maxY, controller.cameraViewport.frame.minY)
            let guidanceFrame = controller.guidanceLabel.convert(controller.guidanceLabel.bounds, to: controller.view)
            XCTAssertLessThan(controller.cameraViewport.frame.maxY, guidanceFrame.minY)
            XCTAssertEqual(controller.guidanceLabel.text, "距離太遠")
            XCTAssertEqual(controller.detailLabel.text, "近一點")
            XCTAssertEqual(controller.qualityView.lighting.state, .passed)
            XCTAssertEqual(controller.qualityView.angle.state, .passed)
            XCTAssertEqual(controller.qualityView.size.state, .failed)
            // 只用純色替代不存在的模擬器相機，不包含使用者照片。
            controller.cameraViewport.backgroundColor = UIColor(white: 0.13, alpha: 1)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: size, format: format).image {
                controller.view.layer.render(in: $0.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "原生介面-距離太遠-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testUnknownAndMultipleFailuresUpdateAllBadgesAndPreserveCustomText() {
        let controller = SkinCaptureViewController(appearance: .init(guidanceMessages: ["moreLight": "請補充光線"])) { _ in }
        controller.loadViewIfNeeded()
        controller.renderGuidance(GuidanceEvaluation(guidance: .moreLight, progress: 0,
            quality: CaptureQuality(lighting: .failed, angle: .failed, size: .passed)))
        XCTAssertEqual(controller.guidanceLabel.text, "請補充光線")
        XCTAssertEqual(controller.qualityView.lighting.accessibilityValue, "需要調整")
        XCTAssertEqual(controller.qualityView.angle.accessibilityValue, "需要調整")
        XCTAssertEqual(controller.qualityView.size.accessibilityValue, "符合")
        controller.renderGuidance(GuidanceEvaluation(guidance: .noFace, progress: 0))
        XCTAssertEqual(controller.guidanceLabel.text, "暫時無法辨識人臉")
        XCTAssertEqual(controller.qualityView.lighting.state, .unknown)
        XCTAssertEqual(controller.qualityView.angle.state, .unknown)
        XCTAssertEqual(controller.qualityView.size.state, .unknown)
    }
}
#endif
