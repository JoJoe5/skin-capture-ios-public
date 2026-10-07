import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skin_capture_example/analysis/analysis_client.dart';
import 'package:skin_capture_example/analysis/sample_report.dart';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

http.StreamedResponse _json(int status, Object body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(Stream.value(bytes), status,
      headers: {'content-type': 'application/json'});
}

class _Recorder {
  _Recorder(this.respond);
  final http.StreamedResponse Function() respond;
  http.BaseRequest? request;
  String body = '';

  PocAnalysisClient client(
          {String token = '',
          String base = 'https://api.test/skin-analytics'}) =>
      PocAnalysisClient(
        settings: AnalysisSettings(apiBaseUrl: base, pocToken: token),
        client: MockClient.streaming((request, stream) async {
          this.request = request;
          body = utf8.decode(await stream.expand((c) => c).toList(),
              allowMalformed: true);
          return respond();
        }),
      );
}

void main() {
  test('POST /poc/skin-analysis：只送 front（image/jpeg），沒有 Authorization',
      () async {
    final recorder = _Recorder(() => _json(200, {
          'report': sampleReportJson,
          'report_error': null,
          'api_validation': {'ok': true},
          'elapsed_s': 12.3,
          'azure': {'raw': 'x' * 10},
        }));
    final result = await recorder
        .client(base: 'https://api.test/skin-analytics/')
        .analyze(_jpeg);

    expect(recorder.request!.method, 'POST');
    expect(recorder.request!.url.toString(),
        'https://api.test/skin-analytics/poc/skin-analysis');
    expect(recorder.request!.headers.containsKey('Authorization'), isFalse);
    expect(recorder.request!.headers.containsKey('X-POC-Token'), isFalse);
    expect(recorder.body, contains('name="front"; filename="face.jpg"'));
    expect(recorder.body.toLowerCase(), contains('content-type: image/jpeg'));
    expect(recorder.body, isNot(contains('system_prompt')));

    expect(result.report!.overallScore, 78);
    expect(result.report!.dimensions.length, 6);
    expect(result.formalApiWouldAccept, isTrue);
    expect(result.error, isNull);
  });

  test('有設定權杖才帶 X-POC-Token', () async {
    final recorder = _Recorder(() => _json(200, {'report': sampleReportJson}));
    await recorder.client(token: ' secret ').analyze(_jpeg);
    expect(recorder.request!.headers['X-POC-Token'], 'secret');
  });

  test('200 內的 report_error：report 為 null，保留 code 與 detail', () async {
    final recorder = _Recorder(() => _json(200, {
          'report': null,
          'report_error': {
            'code': 'PHOTO_REJECTED',
            'message': '照片品質不足',
            'details': [
              {'field': 'front', 'code': 'MULTIPLE_FACES'},
            ],
          },
          'api_validation': {'ok': false},
        }));
    final result = await recorder.client().analyze(_jpeg);
    expect(result.report, isNull);
    expect(result.error!.code, 'PHOTO_REJECTED');
    expect(result.error!.hasDetail('MULTIPLE_FACES'), isTrue);
    expect(result.formalApiWouldAccept, isFalse);
  });

  for (final status in [401, 404, 413, 422, 429, 503]) {
    test('HTTP $status 保留狀態碼與 error.code', () async {
      final recorder = _Recorder(() => _json(status, {
            'error': {'code': 'SOME_CODE', 'message': '訊息', 'details': []},
          }));
      expect(
        recorder.client().analyze(_jpeg),
        throwsA(isA<AnalysisApiException>()
            .having((e) => e.statusCode, 'statusCode', status)
            .having((e) => e.code, 'code', 'SOME_CODE')),
      );
    });
  }

  test('非 JSON 錯誤本文只留狀態碼；斷線沒有狀態碼', () async {
    final html = _Recorder(() => http.StreamedResponse(
        Stream.value(utf8.encode('<html>503</html>')), 503));
    await expectLater(
      html.client().analyze(_jpeg),
      throwsA(isA<AnalysisApiException>()
          .having((e) => e.statusCode, 'statusCode', 503)
          .having((e) => e.error, 'error', isNull)),
    );
    final offline = PocAnalysisClient(
      settings: AnalysisSettings(apiBaseUrl: 'https://api.test'),
      client: MockClient((_) async => throw http.ClientException('斷線')),
    );
    await expectLater(
      offline.analyze(_jpeg),
      throwsA(isA<AnalysisApiException>()
          .having((e) => e.statusCode, 'statusCode', isNull)),
    );
  });

  test('0 分是有效分數、小數保留、依 order 排序', () {
    final recorder = _Recorder(() => _json(200, {
          'report': {
            'overall': {'score': 40},
            'summary': 's',
            'dimensions': [
              {
                'code': 'pores',
                'name': '毛孔',
                'order': 2,
                'score': 80.5,
                'explanation': 'e'
              },
              {
                'code': 'wrinkles',
                'name': '皺紋',
                'order': 1,
                'score': 0,
                'explanation': 'e'
              },
            ],
          },
        }));
    return recorder.client().analyze(_jpeg).then((result) {
      expect([for (final d in result.report!.dimensions) d.code],
          ['wrinkles', 'pores']);
      expect(result.report!.dimensions.first.score, 0);
      expect(result.report!.dimensions.last.score, 80.5);
    });
  });
}
