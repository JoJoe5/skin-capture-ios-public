import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'analysis_models.dart';

const _brand = Color(0xFF0DA185);

/// 顯示檢測報告：總分、摘要、六項分數，以及 Demo 本機拍到的照片。
/// 檢測服務不回傳照片，所以照片由呼叫端以 [photo] 傳入。
class AnalysisReportView extends StatelessWidget {
  const AnalysisReportView({super.key, required this.report, this.photo});
  final AnalysisReport report;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverallCard(report: report),
        const SizedBox(height: 16),
        Text('各項分數', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('0～100 分，分數越高越好。', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final dimension in report.dimensions)
          _DimensionCard(dimension: dimension),
        if (photo != null) ...[
          const SizedBox(height: 16),
          Text('檢測照片', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              photo!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Text('無法預覽照片'),
            ),
          ),
        ],
      ],
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.report});
  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = report.overallScore;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Semantics(
            label: '整體分數 ${score ?? '—'} 分',
            excludeSemantics: true,
            child: SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      key: const ValueKey('overallRing'),
                      value: score == null ? 0 : score / 100,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      backgroundColor: const Color(0xFFE3EBE9),
                      color: _brand,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${score ?? '—'}',
                          key: const ValueKey('overallScore'),
                          style: theme.textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('整體分數', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if ((report.summary ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(report.summary!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          ],
        ],
      ),
    );
  }
}

class _DimensionCard extends StatelessWidget {
  const _DimensionCard({required this.dimension});
  final DimensionResult dimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = dimension.score;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dimension.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(
                score == null
                    ? (dimension.category ?? '—')
                    : _scoreText(score),
                key: ValueKey('score-${dimension.code}'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: _brand),
              ),
            ],
          ),
          if (score != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (score / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: const Color(0xFFE3EBE9),
                color: _brand,
              ),
            ),
          ],
          if (dimension.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(dimension.explanation,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          ],
        ],
      ),
    );
  }

  // 0 是有效分數；整數不顯示小數點，小數保留一位。
  static String _scoreText(double score) =>
      score == score.roundToDouble()
          ? score.round().toString()
          : score.toStringAsFixed(1);
}
