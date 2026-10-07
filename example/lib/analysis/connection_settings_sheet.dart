import 'package:flutter/material.dart';

import 'analysis_client.dart';

/// 檢測連線設定。僅存在記憶體，不寫入磁碟；也可用 --dart-define 預填：
/// SKIN_API_BASE_URL、POC_TOKEN。
class ConnectionSettingsSheet extends StatefulWidget {
  const ConnectionSettingsSheet({super.key, required this.settings});
  final AnalysisSettings settings;

  @override
  State<ConnectionSettingsSheet> createState() =>
      _ConnectionSettingsSheetState();
}

class _ConnectionSettingsSheetState extends State<ConnectionSettingsSheet> {
  late final _api = TextEditingController(text: widget.settings.apiBaseUrl);
  late final _token = TextEditingController(text: widget.settings.pocToken);

  @override
  void dispose() {
    _api.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('檢測連線設定', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('照片由 Demo 上傳到 staging 測試端點；SDK 本身不會上傳。'
                  '設定只保留在這次執行中。'),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('apiBaseUrl'),
                controller: _api,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '檢測服務網址',
                  hintText: 'https://…/skin-analytics',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pocToken'),
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '測試權杖（X-POC-Token，沒設定可留空）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    widget.settings
                      ..apiBaseUrl = _api.text.trim()
                      ..pocToken = _token.text.trim();
                    Navigator.pop(context, true);
                  },
                  child: const Text('儲存'),
                ),
              ),
            ],
          ),
        ),
      );
}
