import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'analysis_client.dart';
import 'analysis_models.dart';
import 'report_view.dart';

/// 離開此頁時回傳，讓首頁知道使用者要重新拍照。
const retakeResult = 'retake';

class _Failure {
  const _Failure(this.title, this.message, {this.retryLabel, this.retry});
  final String title;
  final String message;
  final String? retryLabel;
  final VoidCallback? retry;
}

enum _Phase { running, report, failure }

/// 上傳 SDK 拍到的照片 → 等待同步回應 → 顯示報告或失敗原因。
class AnalysisFlowPage extends StatefulWidget {
  const AnalysisFlowPage({super.key, required this.jpeg, required this.client});
  final Uint8List jpeg;
  final PocAnalysisClient client;

  @override
  State<AnalysisFlowPage> createState() => _AnalysisFlowPageState();
}

class _AnalysisFlowPageState extends State<AnalysisFlowPage> {
  _Phase _phase = _Phase.running;
  PocResult? _result;
  _Failure? _failure;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _phase = _Phase.running);
    try {
      final result = await widget.client.analyze(widget.jpeg);
      // 使用者已離開頁面時丟棄結果。
      if (!mounted) return;
      final report = result.report;
      if (report != null) {
        setState(() {
          _result = result;
          _phase = _Phase.report;
        });
      } else {
        _fail(_describeReportError(result.error));
      }
    } on AnalysisApiException catch (error) {
      _fail(_describeHttpError(error));
    }
  }

  void _fail(_Failure failure) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _phase = _Phase.failure;
    });
  }

  void _retake() => Navigator.of(context).pop(retakeResult);

  /// HTTP 200 內的 report_error，依 code 決定下一步。
  _Failure _describeReportError(AnalysisError? error) {
    switch (error?.code) {
      case 'PHOTO_REJECTED':
        final reason = error!.hasDetail('MULTIPLE_FACES')
            ? '畫面中偵測到多張臉，請只留一個人再拍。'
            : '照片品質不足（可能無臉、失焦、過暗或被遮擋），請重新拍攝。';
        return _Failure('照片無法分析', reason,
            retryLabel: '重新拍攝', retry: _retake);
      case 'ANALYSIS_UNAVAILABLE':
        // 原照片無法產出完整報告，只顯示原因，不提供原照重試。
        return const _Failure('目前無法產生報告', '這張照片無法產生完整報告，請返回。');
      case 'INVALID_MODEL_OUTPUT':
        return _Failure('分析結果不完整', '模型回應不完整，可以再試一次。',
            retryLabel: '重新分析', retry: _run);
      default:
        return _Failure('分析失敗', error?.message ?? '發生未知的錯誤。',
            retryLabel: '重新分析', retry: _run);
    }
  }

  /// HTTP 錯誤用狀態碼判斷，不依 message 判斷流程。
  _Failure _describeHttpError(AnalysisApiException error) {
    switch (error.statusCode) {
      case null:
        return _Failure('連線失敗', error.message ?? '無法連線，請檢查網路與連線設定。',
            retryLabel: '重試', retry: _run);
      case 401:
        return const _Failure('權杖不正確', '請到「檢測連線設定」確認測試權杖。');
      case 404:
        return const _Failure('測試端點尚未啟用', '檢測服務還沒有開放這個測試端點，請稍後再試。');
      case 413:
        return const _Failure('照片過大', '照片超過 10 MB，無法上傳。');
      case 422:
        return _Failure('照片不是有效圖片', '請重新拍攝。',
            retryLabel: '重新拍攝', retry: _retake);
      case 429:
        return _Failure('請求太頻繁', '同時請求過多，請稍候再試。',
            retryLabel: '重試', retry: _run);
      case 503:
        return _Failure('服務暫時無法使用', '檢測服務暫時故障，請稍後再試。',
            retryLabel: '重試', retry: _run);
    }
    return _Failure('請求失敗', error.error?.message ?? 'HTTP ${error.statusCode}',
        retryLabel: '重試', retry: _run);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('肌膚檢測')),
        body: SafeArea(
          child: switch (_phase) {
            _Phase.running => const _Busy(),
            _Phase.report => _buildReport(context),
            _Phase.failure => _buildFailure(context),
          },
        ),
      );

  Widget _buildReport(BuildContext context) {
    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // POC 不擋照片；若正式 API 會拒絕這張，提醒測試者。
          if (result.formalApiWouldAccept == false) ...[
            Container(
              key: const ValueKey('formalApiWarning'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('提醒：這張照片在正式 API 可能會被拒絕（例如解析度不足或方向不符），'
                  '測試報告僅供參考。'),
            ),
            const SizedBox(height: 16),
          ],
          AnalysisReportView(report: result.report!, photo: widget.jpeg),
        ],
      ),
    );
  }

  Widget _buildFailure(BuildContext context) {
    final failure = _failure!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(failure.title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(failure.message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (failure.retry != null)
              FilledButton(
                onPressed: failure.retry,
                child: Text(failure.retryLabel ?? '重試'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('分析中，約需 10～20 秒…'),
          ],
        ),
      );
}
