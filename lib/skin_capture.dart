import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 拍攝設定。亮度為臉部內縮區域的平均 Y 值，正規化為 0～1。
class CaptureOptions {
  const CaptureOptions({
    this.minimumFaceHeight = 0.60,
    this.maximumFaceHeight = 0.80,
    this.centerTolerance = 0.16,
    this.maximumAngle = 0.30,
    this.minimumBrightness = 50 / 255,
    this.maximumBrightness = 170 / 255,
    this.stableDuration = 0.6,
    this.countdownDuration = 1,
    this.maximumImageDimension,
    this.jpegQuality = 0.9,
    this.accentColorArgb = 0xFF0DA185,
    this.title = '正臉拍攝',
    this.confirmText = '使用這張照片',
    this.retakeText = '重新拍攝',
    this.guidanceMessages = const {},
  });

  /// 偵測臉框在預覽中的高度占橢圓引導框高度的比例。
  final double minimumFaceHeight;
  final double maximumFaceHeight;
  final double centerTolerance;

  /// 頭部角度門檻，單位為弧度。
  final double maximumAngle;
  final double minimumBrightness;
  final double maximumBrightness;
  final double stableDuration;
  final double countdownDuration;

  /// null 保留原解析度；有設定則只縮小、不放大。
  final int? maximumImageDimension;
  final double jpegQuality;
  final int accentColorArgb;
  final String title;
  final String confirmText;
  final String retakeText;
  final Map<String, String> guidanceMessages;

  Map<String, Object?> toMap() {
    bool inRange(double value, double low, double high) =>
        value.isFinite && value >= low && value <= high;
    if (!inRange(minimumFaceHeight, 0.1, 0.9) ||
        !inRange(maximumFaceHeight, minimumFaceHeight, 0.95) ||
        maximumFaceHeight <= minimumFaceHeight ||
        !inRange(centerTolerance, 0.01, 0.25) ||
        !inRange(maximumAngle, 0.05, 0.6) ||
        !inRange(minimumBrightness, 0, 1) ||
        !inRange(maximumBrightness, minimumBrightness, 1) ||
        maximumBrightness <= minimumBrightness ||
        !inRange(stableDuration, 0.2, 5) ||
        !inRange(countdownDuration, 1, 5) ||
        !inRange(jpegQuality, 0.5, 1) ||
        (maximumImageDimension != null &&
            (maximumImageDimension! < 640 || maximumImageDimension! > 8192)) ||
        accentColorArgb < 0 ||
        accentColorArgb > 0xFFFFFFFF ||
        title.trim().isEmpty ||
        confirmText.trim().isEmpty ||
        retakeText.trim().isEmpty) {
      throw ArgumentError('拍攝設定不合法');
    }
    return {
      'minimumFaceHeight': minimumFaceHeight,
      'maximumFaceHeight': maximumFaceHeight,
      'centerTolerance': centerTolerance,
      'maximumAngle': maximumAngle,
      'minimumBrightness': minimumBrightness,
      'maximumBrightness': maximumBrightness,
      'stableDuration': stableDuration,
      'countdownDuration': countdownDuration,
      'maximumImageDimension': maximumImageDimension,
      'jpegQuality': jpegQuality,
      'accentColorArgb': accentColorArgb,
      'title': title,
      'confirmText': confirmText,
      'retakeText': retakeText,
      'guidanceMessages': Map<String, String>.from(guidanceMessages),
    };
  }
}

class CaptureResult {
  CaptureResult._(this.jpegBytes, this.width, this.height, this.capturedAt);
  final Uint8List jpegBytes;
  final int width;
  final int height;
  final DateTime capturedAt;
  String get mimeType => 'image/jpeg';

  factory CaptureResult.fromMap(Map<Object?, Object?> map) {
    final bytes = map['jpegBytes'];
    final width = map['width'];
    final height = map['height'];
    final time = map['capturedAtMilliseconds'];
    if (bytes is! Uint8List ||
        bytes.length < 4 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        width is! int ||
        width <= 0 ||
        height is! int ||
        height <= 0 ||
        time is! int ||
        map['mimeType'] != 'image/jpeg') {
      throw const SkinCaptureException('invalid_result', 'SDK 回傳了不完整的照片資料');
    }
    return CaptureResult._(
      Uint8List.fromList(bytes),
      width,
      height,
      DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
    );
  }
}

class SkinCaptureException implements Exception {
  const SkinCaptureException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'SkinCaptureException($code): $message';
}

class SkinCapture {
  static const _channel = MethodChannel('com.skincapture/capture');
  static bool _busy = false;

  /// 開啟原生拍攝畫面；使用者取消時回傳 null，失敗時拋出例外。
  Future<CaptureResult?> capture({
    CaptureOptions options = const CaptureOptions(),
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw const SkinCaptureException(
        'unsupported_platform',
        '目前僅支援 iPhone 的 iOS App',
      );
    }
    final arguments = options.toMap();
    if (_busy) {
      throw const SkinCaptureException('capture_in_progress', '已有拍攝流程進行中');
    }
    _busy = true;
    try {
      final response = await _channel.invokeMapMethod<Object?, Object?>(
        'capture',
        arguments,
      );
      return response == null ? null : CaptureResult.fromMap(response);
    } on PlatformException catch (error) {
      throw SkinCaptureException(error.code, error.message ?? '拍攝失敗');
    } on MissingPluginException {
      throw const SkinCaptureException(
        'plugin_unavailable',
        '請確認 iOS plugin 已完成註冊',
      );
    } finally {
      _busy = false;
    }
  }
}
