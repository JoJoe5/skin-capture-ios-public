import Flutter
import UIKit
import XCTest
@testable import skin_capture

final class RunnerTests: XCTestCase {
    func testUnknownMethodIsRejected() {
        let plugin = SkinCapturePlugin(presenter: nil)
        plugin.handle(FlutterMethodCall(methodName: "unknown", arguments: nil)) { result in
            XCTAssertTrue((result as AnyObject?) === (FlutterMethodNotImplemented as AnyObject))
        }
    }

    func testMissingPresenterReturnsError() {
        let expected = expectation(description: "缺少可顯示畫面時回傳錯誤")
        let plugin = SkinCapturePlugin(presenter: nil)
        plugin.handle(FlutterMethodCall(methodName: "capture", arguments: nil)) { result in
            XCTAssertEqual((result as? FlutterError)?.code, "no_presenter")
            expected.fulfill()
        }
        waitForExpectations(timeout: 2)
    }
}
