import XCTest
@testable import SkinCaptureSDK

final class FaceTrackingWindowTests: XCTestCase {
    func testTrackingCannotExtendTwoSecondDeadlineWithoutNewDetection() {
        var window = FaceTrackingWindow()
        window.confirm(at: 0)
        for time in [0.4, 0.8, 1.2, 1.6, 2.0] { XCTAssertTrue(window.allowTracking(at: time)) }
        XCTAssertFalse(window.allowTracking(at: 2.01))
        XCTAssertFalse(window.allowTracking(at: 2.1))
    }

    func testDroppedFramesClockReversalAndResetDiscardTracking() {
        var window = FaceTrackingWindow()
        window.confirm(at: 1)
        XCTAssertFalse(window.allowTracking(at: 1.6))
        window.confirm(at: 2)
        XCTAssertFalse(window.allowTracking(at: 1.9))
        window.confirm(at: 3)
        window.reset()
        XCTAssertFalse(window.allowTracking(at: 3.1))
    }
}
