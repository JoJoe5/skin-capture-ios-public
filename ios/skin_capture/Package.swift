// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "skin_capture",
    platforms: [.iOS(.v16)],
    products: [.library(name: "skin-capture", targets: ["skin_capture"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(name: "SkinCaptureSDK", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "skin_capture", dependencies: [
            "SkinCaptureSDK", .product(name: "FlutterFramework", package: "FlutterFramework")
        ])
    ]
)
