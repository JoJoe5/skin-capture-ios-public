import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_capture_example/main.dart';

void main() {
  const channel = MethodChannel('com.skincapture/capture');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Demo 使用正式 plugin 並顯示取消結果', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.arguments['minimumFaceHeight'], 0.55);
      expect(call.arguments['maximumFaceHeight'], 0.8);
      expect(call.arguments['targetYawDegrees'], 0);
      return null;
    });
    await tester.pumpWidget(const SkinCaptureDemo());
    expect(find.text('開始拍攝'), findsOneWidget);
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('已取消拍攝'), findsOneWidget);
    expect(find.text('開始拍攝'), findsOneWidget);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('相機錯誤可讀，使用者可以再次拍攝', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'permission_denied',
        message: '請允許相機權限',
      );
    });
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();
    expect(find.text('請允許相機權限'), findsOneWidget);
    expect(find.text('開始拍攝'), findsOneWidget);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('小螢幕套用大小範圍後，下一次拍攝使用新的設定', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<Object?, Object?>? capturedOptions;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedOptions = call.arguments as Map<Object?, Object?>;
      return null;
    });
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.byTooltip('拍攝設定'));
    await tester.pumpAndSettle();
    final slider =
        tester.widget<RangeSlider>(find.byKey(const ValueKey('faceSizeRange')));
    expect(slider.values, const RangeValues(55, 80));
    slider.onChanged!(const RangeValues(55, 75));
    await tester.pump();
    await tester.ensureVisible(find.text('套用'));
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    expect(find.text('臉大小：55～75% · 調整'), findsOneWidget);
    await tester.ensureVisible(find.text('開始拍攝'));
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();
    expect(capturedOptions!['minimumFaceHeight'], 0.55);
    expect(capturedOptions!['maximumFaceHeight'], 0.75);
    expect(capturedOptions!['minimumBrightness'], closeTo(50 / 255, 0.0001));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('取消設定不保存變更，範圍相等時不能套用', (tester) async {
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.byTooltip('拍攝設定'));
    await tester.pumpAndSettle();
    tester
        .widget<RangeSlider>(find.byKey(const ValueKey('faceSizeRange')))
        .onChanged!(const RangeValues(80, 80));
    tester
        .widget<Slider>(find.byKey(const ValueKey('targetYaw')))
        .onChanged!(45);
    await tester.pump();
    expect(find.text('臉大小下限必須小於上限'), findsOneWidget);
    final applyButton = tester.widget<FilledButton>(
      find.ancestor(of: find.text('套用'), matching: find.byType(FilledButton)),
    );
    expect(applyButton.onPressed, isNull);
    Navigator.of(tester.element(find.byType(RangeSlider))).pop();
    await tester.pumpAndSettle();
    expect(find.text('臉大小：55～80% · 調整'), findsOneWidget);
    expect(find.text('目標轉頭角度：0°'), findsOneWidget);
    await tester.tap(find.byTooltip('拍攝設定'));
    await tester.pumpAndSettle();
    expect(tester.widget<RangeSlider>(find.byType(RangeSlider)).values,
        const RangeValues(55, 80));
    Navigator.of(tester.element(find.byType(RangeSlider))).pop();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('恢復預設一起還原臉大小與亮度，套用後回傳正確參數', (tester) async {
    Map<Object?, Object?>? capturedOptions;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedOptions = call.arguments as Map<Object?, Object?>;
      return null;
    });
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.byTooltip('拍攝設定'));
    await tester.pumpAndSettle();
    tester
        .widget<RangeSlider>(find.byType(RangeSlider))
        .onChanged!(const RangeValues(45, 85));
    tester
        .widget<Slider>(find.byKey(const ValueKey('minimumBrightness')))
        .onChanged!(100);
    tester
        .widget<Slider>(find.byKey(const ValueKey('maximumBrightness')))
        .onChanged!(220);
    tester
        .widget<Slider>(find.byKey(const ValueKey('targetYaw')))
        .onChanged!(-45);
    tester
        .widget<Slider>(find.byKey(const ValueKey('angleTolerance')))
        .onChanged!(10);
    await tester.pump();
    await tester.ensureVisible(find.text('恢復預設'));
    await tester.tap(find.text('恢復預設'));
    await tester.pump();
    expect(tester.widget<RangeSlider>(find.byType(RangeSlider)).values,
        const RangeValues(55, 80));
    expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('minimumBrightness')))
            .value,
        50);
    expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('maximumBrightness')))
            .value,
        170);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('targetYaw'))).value,
        0);
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('開始拍攝'));
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();
    expect(capturedOptions!['minimumFaceHeight'], 0.55);
    expect(capturedOptions!['maximumFaceHeight'], 0.8);
    expect(capturedOptions!['minimumBrightness'], closeTo(50 / 255, 0.0001));
    expect(capturedOptions!['maximumBrightness'], closeTo(170 / 255, 0.0001));
    expect(capturedOptions!['targetYawDegrees'], 0);
    expect(capturedOptions!['maximumAngle'], closeTo(0.3, 0.000001));
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('小螢幕套用正負 45 度及自訂角度，下一次拍攝使用目標', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<Object?, Object?>? capturedOptions;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedOptions = call.arguments as Map<Object?, Object?>;
      return null;
    });
    await tester.pumpWidget(const SkinCaptureDemo());
    for (final angle in [45, -45, 30]) {
      await tester.tap(find.byTooltip('拍攝設定'));
      await tester.pumpAndSettle();
      if (angle.abs() == 45) {
        await tester.ensureVisible(find.text('$angle°'));
        await tester.tap(find.text('$angle°'));
      } else {
        tester
            .widget<Slider>(find.byKey(const ValueKey('targetYaw')))
            .onChanged!(angle.toDouble());
      }
      await tester.pump();
      tester
          .widget<Slider>(find.byKey(const ValueKey('angleTolerance')))
          .onChanged!(10);
      await tester.pump();
      await tester.ensureVisible(find.text('套用'));
      await tester.tap(find.text('套用'));
      await tester.pumpAndSettle();
      expect(find.text('目標轉頭角度：$angle°'), findsOneWidget);
      await tester.ensureVisible(find.text('開始拍攝'));
      await tester.tap(find.text('開始拍攝'));
      await tester.pumpAndSettle();
      expect(capturedOptions!['targetYawDegrees'], angle.toDouble());
      expect(capturedOptions!['maximumAngle'], closeTo(0.174533, 0.000001));
      expect(capturedOptions!['title'], '側臉拍攝');
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));
}
