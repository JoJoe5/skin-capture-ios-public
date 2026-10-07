import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_capture/skin_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.skincapture/capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, Object> photo() => {
        'jpegBytes': Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
        'width': 1200,
        'height': 1600,
        'mimeType': 'image/jpeg',
        'capturedAtMilliseconds': 1760000000000,
      };

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('確認拍攝後回傳 JPEG 與尺寸，參數完整傳至原生', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'capture');
      expect(call.arguments['countdownDuration'], 1);
      expect(call.arguments['stableDuration'], 0.6);
      expect(call.arguments['minimumFaceHeight'], 0.55);
      expect(call.arguments['maximumFaceHeight'], 0.8);
      expect(call.arguments['targetYawDegrees'], 0);
      expect(call.arguments['minimumBrightness'], closeTo(50 / 255, 0.0001));
      expect(call.arguments['maximumImageDimension'], 2048);
      return photo();
    });
    final result = await SkinCapture().capture(
      options: const CaptureOptions(maximumImageDimension: 2048),
    );
    expect(result!.mimeType, 'image/jpeg');
    expect(result.width, 1200);
    expect(result.height, 1600);
    expect(result.capturedAt.isUtc, true);
  });

  test('取消回傳 null，下一次仍可拍攝', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await SkinCapture().capture(), isNull);
    expect(await SkinCapture().capture(), isNull);
  });

  test('權限拒絕保留錯誤碼並釋放拍攝狀態', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          throw PlatformException(code: 'permission_denied', message: '請允許相機'),
    );
    await expectLater(
      SkinCapture().capture(),
      throwsA(
        isA<SkinCaptureException>().having(
          (e) => e.code,
          'code',
          'permission_denied',
        ),
      ),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await SkinCapture().capture(), isNull);
  });

  test('重複呼叫不會開啟兩個相機畫面', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final first = SkinCapture().capture();
    await expectLater(
      SkinCapture().capture(),
      throwsA(
        isA<SkinCaptureException>().having(
          (e) => e.code,
          'code',
          'capture_in_progress',
        ),
      ),
    );
    pending.complete(null);
    expect(await first, isNull);
  });

  test('錯誤資料與未註冊 plugin 回傳明確例外', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'width': 0});
    await expectLater(
      SkinCapture().capture(),
      throwsA(
        isA<SkinCaptureException>().having(
          (e) => e.code,
          'code',
          'invalid_result',
        ),
      ),
    );
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      SkinCapture().capture(),
      throwsA(
        isA<SkinCaptureException>().having(
          (e) => e.code,
          'code',
          'plugin_unavailable',
        ),
      ),
    );
  });

  test('非 iOS 平台不嘗試原生呼叫', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(
      SkinCapture().capture(),
      throwsA(
        isA<SkinCaptureException>().having(
          (e) => e.code,
          'code',
          'unsupported_platform',
        ),
      ),
    );
  });

  test('不合法設定在正式模式也會拒絕', () {
    for (final options in [
      const CaptureOptions(minimumBrightness: 0.9, maximumBrightness: 0.1),
      const CaptureOptions(stableDuration: double.nan),
      const CaptureOptions(countdownDuration: 0),
      const CaptureOptions(jpegQuality: 2),
      const CaptureOptions(maximumImageDimension: 1),
      const CaptureOptions(title: ''),
      const CaptureOptions(targetYawDegrees: double.nan),
      const CaptureOptions(targetYawDegrees: double.infinity),
      const CaptureOptions(targetYawDegrees: -61),
      const CaptureOptions(targetYawDegrees: 61),
    ]) {
      expect(options.toMap, throwsArgumentError);
    }
  });

  test('正負目標角度及容差完整傳至原生，包含合法上下限', () async {
    for (final target in [-60.0, -45.0, 0.0, 45.0, 60.0]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.arguments['targetYawDegrees'], target);
        expect(call.arguments['maximumAngle'], closeTo(0.174533, 0.000001));
        return null;
      });
      await SkinCapture().capture(
        options: CaptureOptions(
          targetYawDegrees: target,
          maximumAngle: 0.174533,
        ),
      );
    }
  });
}
