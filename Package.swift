// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SkinCaptureSDK",
    platforms: [.iOS(.v16)],
    products: [.library(name: "SkinCaptureSDK", targets: ["SkinCaptureSDK"])],
    targets: [
        .target(name: "SkinCaptureSDK", path: "ios/skin_capture/Sources/SkinCaptureSDK", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "SkinCaptureSDKTests", dependencies: ["SkinCaptureSDK"])
    ]
)
