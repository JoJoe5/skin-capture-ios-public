import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:skin_capture/skin_capture.dart';

void main() => runApp(const SkinCaptureDemo());

class SkinCaptureDemo extends StatelessWidget {
  const SkinCaptureDemo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '肌膚拍攝引導 Demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0DA185)),
          scaffoldBackgroundColor: const Color(0xFFF4F7F6),
          useMaterial3: true,
        ),
        home: const CaptureHome(),
      );
}

class CaptureHome extends StatefulWidget {
  const CaptureHome({super.key});
  @override
  State<CaptureHome> createState() => _CaptureHomeState();
}

class _CaptureHomeState extends State<CaptureHome> {
  static const _defaults = CaptureOptions();
  final _sdk = SkinCapture();
  CaptureResult? _photo;
  bool _capturing = false;
  String? _message;
  double _minimumBrightness = 50;
  double _maximumBrightness = 170;
  double _minimumFaceHeight = _defaults.minimumFaceHeight;
  double _maximumFaceHeight = _defaults.maximumFaceHeight;
  double _targetYawDegrees = _defaults.targetYawDegrees;
  double _maximumAngle = _defaults.maximumAngle;

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _message = null;
    });
    try {
      final photo = await _sdk.capture(
        options: CaptureOptions(
          minimumFaceHeight: _minimumFaceHeight,
          maximumFaceHeight: _maximumFaceHeight,
          targetYawDegrees: _targetYawDegrees,
          maximumAngle: _maximumAngle,
          title: _targetYawDegrees == 0 ? '正臉拍攝' : '側臉拍攝',
          minimumBrightness: _minimumBrightness / 255,
          maximumBrightness: _maximumBrightness / 255,
        ),
      );
      if (!mounted) return;
      setState(() {
        if (photo != null) _photo = photo;
        _message = photo == null ? '已取消拍攝' : '照片已準備完成';
      });
    } on SkinCaptureException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on ArgumentError {
      if (mounted) setState(() => _message = '拍攝設定不合法，請重新調整');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _showSettings() async {
    var minimum = _minimumBrightness;
    var maximum = _maximumBrightness;
    var minimumFace = (_minimumFaceHeight * 100).roundToDouble();
    var maximumFace = (_maximumFaceHeight * 100).roundToDouble();
    var targetYaw = _targetYawDegrees;
    var angleTolerance = _maximumAngle * 180 / math.pi;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('拍攝設定',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    const Text('調整後按「套用」，再開始拍攝測試。'),
                    const SizedBox(height: 20),
                    Text(
                        '臉在框內的大小：${minimumFace.round()}～${maximumFace.round()}%'),
                    RangeSlider(
                      key: const ValueKey('faceSizeRange'),
                      values: RangeValues(minimumFace, maximumFace),
                      min: 40,
                      max: 90,
                      divisions: 50,
                      labels: RangeLabels(
                        '${minimumFace.round()}%',
                        '${maximumFace.round()}%',
                      ),
                      semanticFormatterCallback: (value) => '${value.round()}%',
                      onChanged: (values) => update(() {
                        minimumFace = values.start.roundToDouble();
                        maximumFace = values.end.roundToDouble();
                      }),
                    ),
                    const Text('下限調小，可以離鏡頭更遠；上限調大，允許靠得更近。'),
                    if (minimumFace >= maximumFace)
                      const Text('臉大小下限必須小於上限',
                          style: TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    Text('亮度下限：${minimum.round()}'),
                    Slider(
                      key: const ValueKey('minimumBrightness'),
                      value: minimum,
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (value) => update(() => minimum = value),
                    ),
                    Text('亮度上限：${maximum.round()}'),
                    Slider(
                      key: const ValueKey('maximumBrightness'),
                      value: maximum,
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (value) => update(() => maximum = value),
                    ),
                    if (minimum >= maximum)
                      const Text('下限必須小於上限',
                          style: TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    Text('目標轉頭角度：${targetYaw.round()}°'),
                    Slider(
                      key: const ValueKey('targetYaw'),
                      value: targetYaw,
                      min: -60,
                      max: 60,
                      divisions: 120,
                      label: '${targetYaw.round()}°',
                      onChanged: (value) =>
                          update(() => targetYaw = value.roundToDouble()),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final angle in [-45.0, 0.0, 45.0])
                          ChoiceChip(
                            label: Text(
                                angle == 0 ? '正面 0°' : '${angle.round()}°'),
                            selected: targetYaw == angle,
                            onSelected: (_) => update(() => targetYaw = angle),
                          ),
                      ],
                    ),
                    const Text('正負代表相反的轉頭方向，拍攝畫面顯示目前角度。'),
                    Text('角度容許誤差：±${angleTolerance.toStringAsFixed(1)}°'),
                    Slider(
                      key: const ValueKey('angleTolerance'),
                      value: angleTolerance,
                      min: 3,
                      max: 30,
                      divisions: 27,
                      label: '±${angleTolerance.toStringAsFixed(1)}°',
                      onChanged: (value) =>
                          update(() => angleTolerance = value),
                    ),
                    const Text('容許目標前後的角度偏差；抬頭與歪頭也使用相同門檻。'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => update(() {
                            minimum = 50;
                            maximum = 170;
                            targetYaw = _defaults.targetYawDegrees;
                            angleTolerance =
                                _defaults.maximumAngle * 180 / math.pi;
                            minimumFace = (_defaults.minimumFaceHeight * 100)
                                .roundToDouble();
                            maximumFace = (_defaults.maximumFaceHeight * 100)
                                .roundToDouble();
                          }),
                          child: const Text('恢復預設'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed:
                              minimum < maximum && minimumFace < maximumFace
                                  ? () => Navigator.pop(sheetContext, true)
                                  : null,
                          child: const Text('套用'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _minimumBrightness = minimum;
        _maximumBrightness = maximum;
        _minimumFaceHeight = minimumFace / 100;
        _maximumFaceHeight = maximumFace / 100;
        _targetYawDegrees = targetYaw;
        _maximumAngle = angleTolerance * math.pi / 180;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('肌膚拍攝引導'),
        actions: [
          IconButton(
            onPressed: _capturing ? null : _showSettings,
            icon: const Icon(Icons.tune),
            tooltip: '拍攝設定',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.face_retouching_natural,
                      size: 64,
                      color: Color(0xFF0DA185),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '拍一張清楚的正臉照片',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '面向均勻光源，露出完整臉部。\n跟著提示調整位置，保持不動後會自動拍照。',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _capturing ? null : _capture,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(_capturing ? '拍攝中…' : '開始拍攝'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _capturing ? null : _showSettings,
                      child: Text(
                        '臉大小：${(_minimumFaceHeight * 100).round()}～${(_maximumFaceHeight * 100).round()}% · 調整',
                      ),
                    ),
                    Text('目標轉頭角度：${_targetYawDegrees.round()}°'),
                  ],
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_message!, textAlign: TextAlign.center),
                ),
              if (photo != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(
                    photo.jpegBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        const Text('無法預覽照片'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${photo.width} × ${photo.height} · JPEG · '
                  '${(photo.jpegBytes.length / 1024).toStringAsFixed(0)} KB',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  '照片保留在這次操作中，可交由 App 接續檢測。',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
