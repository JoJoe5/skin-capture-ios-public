import XCTest
@testable import SkinCaptureSDK

final class CaptureCountdownTests: XCTestCase {
    func testPauseNearShutterNeverExpiresAndResumePreservesRemainingTime() {
        var countdown = CaptureCountdown()
        countdown.start(at: 0)
        countdown.setPaused(true, at: 0.9)
        countdown.setPaused(true, at: 1.0)
        XCTAssertNil(countdown.remaining(at: 1.1, duration: 1))
        countdown.setPaused(false, at: 1.2)
        XCTAssertEqual(countdown.remaining(at: 1.2, duration: 1)!, 0.1, accuracy: 0.0001)
        XCTAssertGreaterThan(countdown.remaining(at: 1.25, duration: 1)!, 0)
        XCTAssertLessThanOrEqual(countdown.remaining(at: 1.31, duration: 1)!, 0)
    }

    func testRepeatedPausesAccumulateOnlyValidTimeAndResetCancelsCountdown() {
        var countdown = CaptureCountdown()
        countdown.start(at: 0)
        countdown.setPaused(true, at: 0.2)
        countdown.setPaused(false, at: 0.4)
        countdown.setPaused(true, at: 0.6)
        countdown.setPaused(false, at: 0.8)
        XCTAssertEqual(countdown.remaining(at: 1.0, duration: 1)!, 0.4, accuracy: 0.0001)
        countdown.reset()
        XCTAssertNil(countdown.remaining(at: 2, duration: 1))
        countdown.start(at: 2)
        XCTAssertEqual(countdown.remaining(at: 2, duration: 1), 1)
    }
}
