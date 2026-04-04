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
  bool _obscure = true;

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

  Future<void> _saveApiKey() async {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appState = ManidocApp.of(context);
    final currentLocale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // アカウント
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

          // Gemini APIキー
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.geminiApiKey,
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(l.geminiApiKeyHint,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l.apiKeyLabel,
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l.geminiModel,
                      hintText: 'gemini-2.0-flash',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _saveApiKey,
                    child: Text(l.save),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 言語
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.language,
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'ja',
                        label: Text(l.languageJa),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(l.languageEn),
                      ),
                    ],
                    selected: {currentLocale},
                    onSelectionChanged: (selected) {
                      appState?.setLocale(Locale(selected.first));
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
