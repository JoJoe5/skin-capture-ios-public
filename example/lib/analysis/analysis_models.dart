// 肌膚檢測 POC 端點（skin-analytics POST /poc/skin-analysis）的資料模型。
// 只在 Demo 使用；原生 SDK 不呼叫檢測 API。

class AnalysisErrorDetail {
  const AnalysisErrorDetail({this.field, this.code});
  final String? field;
  final String? code;

  factory AnalysisErrorDetail.fromJson(Map<String, dynamic> json) =>
      AnalysisErrorDetail(
        field: json['field'] as String?,
        code: json['code'] as String?,
      );
}

/// API 的錯誤物件，HTTP 錯誤的 error 與 200 回應內的 report_error 共用。
class AnalysisError {
  const AnalysisError({
    required this.code,
    required this.message,
    this.details = const [],
  });
  final String code;
  final String message;
  final List<AnalysisErrorDetail> details;

  /// 流程判斷請用 code 與 detail code，不用 message。
  bool hasDetail(String code) => details.any((item) => item.code == code);

  factory AnalysisError.fromJson(Map<String, dynamic> json) => AnalysisError(
        code: json['code'] as String? ?? 'UNKNOWN',
        message: json['message'] as String? ?? '',
        details: [
          for (final item in (json['details'] as List<dynamic>? ?? const []))
            AnalysisErrorDetail.fromJson(item as Map<String, dynamic>),
        ],
      );
}

class DimensionResult {
  const DimensionResult({
    required this.code,
    required this.name,
    required this.order,
    required this.explanation,
    this.score,
    this.category,
  });
  final String code;
  final String name;
  final int order;

  /// 0～100，越高越好，0 是有效分數，可能為小數。
  final double? score;
  final String? category;
  final String explanation;

  factory DimensionResult.fromJson(Map<String, dynamic> json) =>
      DimensionResult(
        code: json['code'] as String,
        name: json['name'] as String? ?? json['code'] as String,
        order: (json['order'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble(),
        category: json['category'] as String?,
        explanation: json['explanation'] as String? ?? '',
      );
}

class AnalysisReport {
  const AnalysisReport({
    this.overallScore,
    this.summary,
    this.dimensions = const [],
  });
  final int? overallScore;
  final String? summary;
  final List<DimensionResult> dimensions;

  factory AnalysisReport.fromJson(Map<String, dynamic> json) {
    final overall = json['overall'] as Map<String, dynamic>?;
    return AnalysisReport(
      overallScore: (overall?['score'] as num?)?.round(),
      summary: json['summary'] as String?,
      dimensions: [
        for (final item in (json['dimensions'] as List<dynamic>? ?? const []))
          DimensionResult.fromJson(item as Map<String, dynamic>),
      ]..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}

/// POC 端點 HTTP 200 的內容：成功時有 [report]，失敗時有 [error]。
class PocResult {
  const PocResult({this.report, this.error, this.formalApiWouldAccept});
  final AnalysisReport? report;
  final AnalysisError? error;

  /// 來自 api_validation.ok：這張照片在正式 API 是否會被放行；POC 本身不擋。
  final bool? formalApiWouldAccept;

  factory PocResult.fromJson(Map<String, dynamic> json) {
    final report = json['report'] as Map<String, dynamic>?;
    final error = json['report_error'] as Map<String, dynamic>?;
    final validation = json['api_validation'];
    return PocResult(
      report: report == null ? null : AnalysisReport.fromJson(report),
      error: error == null ? null : AnalysisError.fromJson(error),
      formalApiWouldAccept: validation is Map ? validation['ok'] as bool? : null,
    );
  }
}
