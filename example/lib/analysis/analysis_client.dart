import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'analysis_models.dart';

/// 連線設定。網址與權杖不寫進 git，由 --dart-define 或 Demo 的連線設定輸入，
/// 只存在記憶體。
class AnalysisSettings {
  AnalysisSettings({
    this.apiBaseUrl = const String.fromEnvironment('SKIN_API_BASE_URL'),
    this.pocToken = const String.fromEnvironment('POC_TOKEN'),
  });

  /// 檢測服務根網址（不含 /poc/skin-analysis），例如 https://…/skin-analytics。
  String apiBaseUrl;

  /// staging 有設 POC_TOKEN 時才需要；以 X-POC-Token 送出。
  String pocToken;

  bool get isComplete => apiBaseUrl.trim().isNotEmpty;
}

/// 呼叫端可辨識的失敗：HTTP 錯誤帶 [error] 與 [statusCode]，連線問題只有 [message]。
class AnalysisApiException implements Exception {
  AnalysisApiException({this.statusCode, this.error, this.message});
  final int? statusCode;
  final AnalysisError? error;
  final String? message;

  String get code => error?.code ?? 'NETWORK';

  @override
  String toString() =>
      'AnalysisApiException($statusCode, $code, ${error?.message ?? message})';
}

/// 同步 POC 檢測端點：一次上傳一張正面照，等到報告回來（約 10～17 秒）。
class PocAnalysisClient {
  PocAnalysisClient({required this.settings, http.Client? client})
      : _client = client ?? http.Client();
  final AnalysisSettings settings;
  final http.Client _client;

  /// 服務端通常 10～17 秒回應，客戶端逾時至少 60 秒。
  static const timeout = Duration(seconds: 90);

  Future<PocResult> analyze(Uint8List jpeg) async {
    final request = http.MultipartRequest('POST', _uri)
      ..files.add(http.MultipartFile.fromBytes(
        'front',
        jpeg,
        filename: 'face.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    final token = settings.pocToken.trim();
    if (token.isNotEmpty) request.headers['X-POC-Token'] = token;

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on Object catch (error) {
      throw AnalysisApiException(message: '無法連線到檢測服務：${_brief(error)}');
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode == 200) {
      try {
        return PocResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
      } on Object {
        throw AnalysisApiException(
          statusCode: 200,
          message: '檢測服務回傳的內容無法解讀',
        );
      }
    }
    AnalysisError? error;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['error'] is Map) {
        error =
            AnalysisError.fromJson(decoded['error'] as Map<String, dynamic>);
      }
    } on FormatException {
      // 非 JSON 的錯誤本文（例如 ALB 的 503 頁面）只保留狀態碼。
    }
    throw AnalysisApiException(statusCode: response.statusCode, error: error);
  }

  Uri get _uri {
    var base = settings.apiBaseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return Uri.parse('$base/poc/skin-analysis');
  }
}

String _brief(Object error) {
  final text = error.toString();
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}
