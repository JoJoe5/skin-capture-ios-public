import Flutter
import UIKit
#if SWIFT_PACKAGE
import SkinCaptureSDK
#endif

public final class SkinCapturePlugin: NSObject, FlutterPlugin {
    private weak var presenter: UIViewController?
    private var registrar: FlutterPluginRegistrar?
    private var activeController: SkinCaptureViewController?

    init(presenter: UIViewController?) { self.presenter = presenter }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.skincapture/capture", binaryMessenger: registrar.messenger())
        let plugin = SkinCapturePlugin(presenter: nil)
        plugin.registrar = registrar
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "capture" else { result(FlutterMethodNotImplemented); return }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                result(FlutterError(code: "plugin_unavailable", message: "拍攝介面已卸載", details: nil))
                return
            }
            self.beginCapture(arguments: call.arguments, result: result)
        }
    }

    private func beginCapture(arguments: Any?, result: @escaping FlutterResult) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            result(FlutterError(code: "unsupported_device", message: "目前僅支援 iPhone", details: nil))
            return
        }
        guard activeController == nil else {
            result(FlutterError(code: "capture_in_progress", message: "已有拍攝流程進行中", details: nil))
            return
        }
        let args = arguments as? [String: Any] ?? [:]
        func number(_ key: String, _ fallback: Double) -> Double { (args[key] as? NSNumber)?.doubleValue ?? fallback }
        let config = CaptureConfiguration(
            minimumFaceHeight: number("minimumFaceHeight", 0.55),
            maximumFaceHeight: number("maximumFaceHeight", 0.80),
            centerTolerance: number("centerTolerance", 0.16), maximumAngle: number("maximumAngle", 0.30),
            targetYawDegrees: number("targetYawDegrees", 0),
            minimumBrightness: number("minimumBrightness", 50 / 255),
            maximumBrightness: number("maximumBrightness", 170 / 255),
            stableDuration: number("stableDuration", 0.6), countdownDuration: number("countdownDuration", 1),
            maximumImageDimension: (args["maximumImageDimension"] as? NSNumber)?.intValue,
            jpegQuality: number("jpegQuality", 0.9)
        )
        guard config.isValid else {
            result(FlutterError(code: "invalid_configuration", message: "拍攝設定不合法", details: nil))
            return
        }
        // Flutter 的隱含引擎可能先註冊 plugin、稍後才掛上控制器，呼叫時再取得。
        guard let root = registrar?.viewController ?? presenter, root.viewIfLoaded?.window != nil else {
            result(FlutterError(code: "no_presenter", message: "找不到可顯示相機的 Flutter 畫面", details: nil))
            return
        }
        var top = root
        while let next = top.presentedViewController { top = next }
        guard !top.isBeingDismissed, !top.isBeingPresented else {
            result(FlutterError(code: "presentation_busy", message: "畫面正在切換，請稍後重試", details: nil))
            return
        }
        let argb = (args["accentColorArgb"] as? NSNumber)?.uint32Value ?? 0xFF0DA185
        let color = UIColor(red: CGFloat((argb >> 16) & 255) / 255,
                            green: CGFloat((argb >> 8) & 255) / 255,
                            blue: CGFloat(argb & 255) / 255, alpha: CGFloat((argb >> 24) & 255) / 255)
        let appearance = CaptureAppearance(accentColor: color,
            title: args["title"] as? String ?? "正臉拍攝",
            confirmText: args["confirmText"] as? String ?? "使用這張照片",
            retakeText: args["retakeText"] as? String ?? "重新拍攝",
            guidanceMessages: args["guidanceMessages"] as? [String: String] ?? [:])
        let controller = SkinCaptureViewController(configuration: config, appearance: appearance) { [weak self] outcome in
            guard let self, let active = self.activeController else { return }
            active.dismiss(animated: true) {
                self.activeController = nil
                switch outcome {
                case .success(let photo):
                    if let photo {
                        result(["jpegBytes": FlutterStandardTypedData(bytes: photo.jpegData),
                                "width": photo.width, "height": photo.height, "mimeType": photo.mimeType,
                                "capturedAtMilliseconds": Int64(photo.capturedAt.timeIntervalSince1970 * 1000)])
                    } else { result(nil) }
                case .failure(let error):
                    result(FlutterError(code: Self.code(for: error), message: error.localizedDescription, details: nil))
                }
            }
        }
        activeController = controller
        top.present(controller, animated: true)
    }

    private static func code(for error: SkinCaptureError) -> String {
        switch error {
        case .invalidConfiguration: return "invalid_configuration"
        case .permissionDenied: return "permission_denied"
        case .cameraUnavailable: return "camera_unavailable"
        case .configurationFailed: return "configuration_failed"
        case .interrupted: return "camera_interrupted"
        case .analysisFailed: return "analysis_failed"
        case .photoFailed: return "photo_failed"
        case .missingCameraUsageDescription: return "missing_camera_usage_description"
        }
    }
}
