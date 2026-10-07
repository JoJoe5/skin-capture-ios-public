import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_capture_example/analysis/analysis_client.dart';
import 'package:skin_capture_example/analysis/analysis_flow_page.dart';
import 'package:skin_capture_example/analysis/analysis_models.dart';
import 'package:skin_capture_example/analysis/report_view.dart';
import 'package:skin_capture_example/analysis/sample_report.dart';
import 'package:skin_capture_example/main.dart';

// 1x1 PNG，讓 Image.memory 在測試中可解碼。
final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

/// 依序回應每次呼叫；最後一個回應會重複使用。
PocAnalysisClient _client(List<(int, Object)> responses, {List<int>? calls}) {
  var index = 0;
  return PocAnalysisClient(
    settings: AnalysisSettings(apiBaseUrl: 'https://api.test/skin-analytics'),
    client: MockClient.streaming((request, stream) async {
      await stream.drain<void>();
      calls?.add(index);
      final (status, body) =
          responses[index < responses.length ? index : responses.length - 1];
      index++;
      final bytes = utf8.encode(jsonEncode(body));
      return http.StreamedResponse(Stream.value(bytes), status,
          headers: {'content-type': 'application/json'});
    }),
  );
}

const _ok = (
  200,
  {
    'report': sampleReportJson,
    'api_validation': {'ok': true},
  }
);

Map<String, Object?> _reportError(String code, [List<Object> details = const []]) => {
      'report': null,
      'report_error': {'code': code, 'message': 'x', 'details': details},
    };

/// 開啟分析頁，回傳 pop 時帶回的結果（尚未 pop 時為 null）。
Future<void> _open(WidgetTester tester, PocAnalysisClient client,
    {void Function(String?)? onResult}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          final result = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => AnalysisFlowPage(jpeg: _pixel, client: client),
            ),
          );
          onResult?.call(result);
        },
        child: const Text('開啟'),
      ),
    ),
  ));
  await tester.tap(find.text('開啟'));
  await tester.pumpAndSettle();
}

/// 讓相機 channel 回傳一張照片（PNG 位元組冒充 JPEG 檔頭僅供預覽測試）。
void _mockCapture(WidgetTester tester) {
  const channel = MethodChannel('com.skincapture/capture');
  final bytes = Uint8List.fromList([0xFF, 0xD8, ..._pixel]);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => {
            'jpegBytes': bytes,
            'width': 1,
            'height': 1,
            'capturedAtMilliseconds': 0,
            'mimeType': 'image/jpeg',
          });
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
}

void main() {
  testWidgets('成功：顯示總分、六項分數、摘要與本機照片', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _open(tester, _client([_ok]));

    expect(find.byKey(const ValueKey('overallScore')), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    for (final name in ['皺紋', '毛孔', '痘痘', '斑點', '黑眼圈', '眼袋']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.textContaining('痘痘與眼袋狀況較佳'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('formalApiWarning')), findsNothing);
  });

  testWidgets('正式 API 會拒絕這張照片時顯示提醒，但仍顯示報告', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _open(
      tester,
      _client([
        (
          200,
          {
            'report': sampleReportJson,
            'api_validation': {'ok': false},
          }
        ),
      ]),
    );
    expect(find.byKey(const ValueKey('formalApiWarning')), findsOneWidget);
    expect(find.byKey(const ValueKey('overallScore')), findsOneWidget);
  });

  testWidgets('PHOTO_REJECTED（多張臉）提示重拍並把重拍結果交回首頁', (tester) async {
    String? result;
    await _open(
      tester,
      _client([
        (
          200,
          _reportError('PHOTO_REJECTED', [
            {'field': 'front', 'code': 'MULTIPLE_FACES'},
          ])
        ),
      ]),
      onResult: (value) => result = value,
    );
    expect(find.text('照片無法分析'), findsOneWidget);
    expect(find.textContaining('多張臉'), findsOneWidget);
    await tester.tap(find.text('重新拍攝'));
    await tester.pumpAndSettle();
    expect(result, retakeResult);
  });

  testWidgets('ANALYSIS_UNAVAILABLE 只顯示原因，不提供重試', (tester) async {
    await _open(tester, _client([(200, _reportError('ANALYSIS_UNAVAILABLE'))]));
    expect(find.text('目前無法產生報告'), findsOneWidget);
    expect(find.text('重新分析'), findsNothing);
    expect(find.text('返回'), findsOneWidget);
  });

  testWidgets('INVALID_MODEL_OUTPUT 可重試，重試後顯示報告', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <int>[];
    await _open(
      tester,
      _client([(200, _reportError('INVALID_MODEL_OUTPUT')), _ok], calls: calls),
    );
    expect(find.text('分析結果不完整'), findsOneWidget);
    await tester.tap(find.text('重新分析'));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    expect(find.byKey(const ValueKey('overallScore')), findsOneWidget);
  });

  testWidgets('HTTP 404 說明端點尚未啟用且不提供重試', (tester) async {
    await _open(tester, _client([(404, {'error': {'code': 'NOT_FOUND', 'message': '', 'details': []}})]));
    expect(find.text('測試端點尚未啟用'), findsOneWidget);
    expect(find.text('重試'), findsNothing);
  });

  testWidgets('HTTP 503 可重試', (tester) async {
    await _open(tester, _client([(503, {'error': {'code': 'SERVICE_UNAVAILABLE', 'message': '', 'details': []}})]));
    expect(find.text('服務暫時無法使用'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
  });

  testWidgets('分析中先顯示等待說明', (tester) async {
    final client = PocAnalysisClient(
      settings: AnalysisSettings(apiBaseUrl: 'https://api.test'),
      client: MockClient.streaming((request, stream) async {
        await stream.drain<void>();
        return http.StreamedResponse(const Stream.empty(), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: AnalysisFlowPage(jpeg: _pixel, client: client),
    ));
    expect(find.text('分析中，約需 10～20 秒…'), findsOneWidget);
    // 空回應無法解讀，結束後顯示失敗頁。
    await tester.pumpAndSettle();
    expect(find.text('請求失敗'), findsOneWidget);
  });

  testWidgets('報告畫面：0 分正常顯示、小數保留一位', (tester) async {
    final dims = sampleReportJson['dimensions'] as List;
    final json = {
      ...sampleReportJson,
      'dimensions': [
        {...dims.first as Map<String, dynamic>, 'score': 0},
        {...dims[1] as Map<String, dynamic>, 'score': 76.5},
      ],
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AnalysisReportView(report: AnalysisReport.fromJson(json)),
        ),
      ),
    ));
    expect(tester.widget<Text>(find.byKey(const ValueKey('score-wrinkles'))).data, '0');
    expect(tester.widget<Text>(find.byKey(const ValueKey('score-pores'))).data, '76.5');
  });

  testWidgets('呼叫檢測 API 預設關閉：拍完照只預覽，沒有任何送出入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _mockCapture(tester);
    await tester.pumpWidget(const SkinCaptureDemo());

    expect(tester.widget<Switch>(find.byKey(const ValueKey('callApiSwitch'))).value,
        isFalse);
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();

    expect(find.text('照片已準備完成'), findsOneWidget);
    expect(find.text('送出肌膚檢測'), findsNothing);
    expect(find.text('預覽範例報告'), findsNothing);
    expect(find.byTooltip('檢測連線設定'), findsNothing);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('打開開關才出現送出入口，關掉後入口消失', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _mockCapture(tester);
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('callApiSwitch')));
    await tester.pumpAndSettle();
    expect(find.text('送出肌膚檢測'), findsOneWidget);
    expect(find.byTooltip('檢測連線設定'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('callApiSwitch')));
    await tester.pumpAndSettle();
    expect(find.text('送出肌膚檢測'), findsNothing);
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('開關打開但尚未設定網址：不送出，並提示先完成設定', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _mockCapture(tester);
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.text('開始拍攝'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('callApiSwitch')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('送出肌膚檢測'));
    await tester.pumpAndSettle();
    expect(find.text('檢測連線設定'), findsWidgets); // 設定面板開啟
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('請先完成檢測連線設定'), findsOneWidget);
    expect(find.text('肌膚檢測'), findsNothing); // 沒有進入分析頁
  }, variant: TargetPlatformVariant({TargetPlatform.iOS}));

  testWidgets('首頁可預覽範例報告', (tester) async {
    await tester.pumpWidget(const SkinCaptureDemo());
    await tester.tap(find.byKey(const ValueKey('callApiSwitch')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('預覽範例報告'));
    await tester.tap(find.text('預覽範例報告'));
    await tester.pumpAndSettle();
    expect(find.text('範例報告'), findsOneWidget);
    expect(find.byKey(const ValueKey('overallScore')), findsOneWidget);
  });
}
