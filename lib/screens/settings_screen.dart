import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gemini = GeminiService();
  final _auth = AuthService();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _localLlmEndpointController =
      TextEditingController(text: 'http://localhost:1234/v1');
  bool _obscure = true;
  String _provider = 'gemini'; // gemini, localllm

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await _gemini.getApiKey();
    final model = await _gemini.getModel();
    if (!mounted) return;
    if (key != null) _apiKeyController.text = key;
    _modelController.text = model;
  }

  Future<void> _save() async {
    await _gemini.setApiKey(_apiKeyController.text.trim());
    await _gemini.setModel(_modelController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).apiKeySaved)),
    );
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _localLlmEndpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appState = ManidocApp.of(context);
    final currentLocale = Localizations.localeOf(context).languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // アカウント（Android版のみ）
          if (!Platform.isWindows) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.account,
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Text(_auth.displayName),
                    Text(_auth.email,
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: Text(l.signOut),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 画像生成 / アシスタント設定
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.settingsSectionAi,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 20),

                  // 言語 (Language)
                  _buildRow(
                    context,
                    label: l.settingsLanguageLabel,
                    child: DropdownButtonFormField<String>(
                      value: currentLocale,
                      decoration: _inputDecoration(),
                      items: const [
                        DropdownMenuItem(
                            value: 'ja', child: Text('日本語 (Japanese)')),
                        DropdownMenuItem(
                            value: 'en', child: Text('English')),
                      ],
                      onChanged: (value) {
                        if (value != null) appState?.setLocale(Locale(value));
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // AIプロバイダ
                  _buildRow(
                    context,
                    label: l.settingsProviderLabel,
                    child: DropdownButtonFormField<String>(
                      value: _provider,
                      decoration: _inputDecoration(),
                      items: const [
                        DropdownMenuItem(
                            value: 'gemini',
                            child: Text('Gemini API (Imagen 3)')),
                        DropdownMenuItem(
                            value: 'localllm',
                            child: Text('Local LLM')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _provider = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Gemini設定パネル
                  if (_provider == 'gemini')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildRow(
                            context,
                            label: l.settingsApiKeyLabel,
                            child: TextField(
                              controller: _apiKeyController,
                              obscureText: _obscure,
                              decoration: _inputDecoration().copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                      size: 20),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildRow(
                            context,
                            label: l.settingsModelLabel,
                            child: TextField(
                              controller: _modelController,
                              decoration: _inputDecoration().copyWith(
                                hintText: 'gemini-2.5-flash',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 128),
                            child: InkWell(
                              onTap: () {
                                // URLをクリップボードにコピー（Flutterデスクトップでは直接ブラウザ起動が面倒なため）
                                // TODO: url_launcher 追加後は launchUrl に変更
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'https://ai.google.dev/gemini-api/docs/models/gemini'),
                                  ),
                                );
                              },
                              child: Text(
                                l.settingsModelListLink,
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // LocalLLM設定パネル
                  if (_provider == 'localllm')
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _buildRow(
                        context,
                        label: l.settingsEndpointLabel,
                        child: TextField(
                          controller: _localLlmEndpointController,
                          decoration: _inputDecoration().copyWith(
                            hintText: 'http://localhost:1234/v1',
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                  Text(
                    l.settingsApiKeyHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),

                  // 保存ボタン
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(l.save),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration() => const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  Widget _buildRow(BuildContext context,
      {required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}
