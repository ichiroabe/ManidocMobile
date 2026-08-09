import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../services/gemini_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gemini = GeminiService();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _imageModelController = TextEditingController();
  final _localLlmEndpointController =
      TextEditingController(text: 'http://localhost:1234/v1');
  bool _obscure = true;
  String _provider = 'gemini'; // gemini, localllm

  // 🔄ボタンでAPIキーから取得したモデル一覧(取得前は手入力)
  List<String> _fetchedModels = [];
  List<String> _fetchedImageModels = [];
  String _selectedModel = 'custom';
  String _selectedImageModel = 'custom';
  bool _loadingModels = false;
  String? _modelsError;
  String? _modelsInfo;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await _gemini.getApiKey();
    final model = await _gemini.getModel();
    final imageModel = await _gemini.getImageModel();
    // 前回取得した一覧を先に出す（毎回取りに行かずに選べるように）
    final cachedText = await _gemini.getCachedModels();
    final cachedImage = await _gemini.getCachedImageModels();
    if (!mounted) return;
    if (key != null) _apiKeyController.text = key;
    _modelController.text = model;
    _imageModelController.text = imageModel;
    setState(() {
      _fetchedModels = cachedText;
      _fetchedImageModels = cachedImage;
      _selectedModel = cachedText.contains(model) ? model : 'custom';
      _selectedImageModel =
          cachedImage.contains(imageModel) ? imageModel : 'custom';
    });

    // キーはあるが一覧を持っていない（＝一度も取れていない）なら取りに行く。
    // 🔄ボタンに気付かないと手入力のままになるため。
    if (key != null && key.isNotEmpty && cachedText.isEmpty) {
      await _fetchModels();
    }
  }

  Future<void> _save() async {
    final key = _apiKeyController.text.trim();
    await _gemini.setApiKey(key);
    await _gemini.setModel(_modelController.text.trim());
    await _gemini.setImageModel(_imageModelController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).apiKeySaved)),
    );
    // 保存したキーで使えるモデルをその場で出す
    if (key.isNotEmpty && _fetchedModels.isEmpty) {
      await _fetchModels();
    }
  }

  // 🔄ボタン: 入力中のAPIキーで使えるモデル一覧を取り直す
  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
      _modelsInfo = null;
    });
    try {
      final models = await _gemini.listModels(_apiKeyController.text);
      if (!mounted) return;
      final current = _modelController.text.trim();
      final currentImage = _imageModelController.text.trim();
      setState(() {
        _fetchedModels = models.text;
        _fetchedImageModels = models.image;
        _selectedModel = models.text.contains(current) ? current : 'custom';
        _selectedImageModel =
            models.image.contains(currentImage) ? currentImage : 'custom';
        // 画像0件のときに成功か失敗か分からなくなるので件数を出す
        _modelsInfo = AppLocalizations.of(context)
            .settingsModelsFetched(models.text.length, models.image.length);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _modelsError =
          '${AppLocalizations.of(context).settingsModelsFetchFailed}\n$e');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  // キーが変わったら取得済み一覧は当てにならないので破棄
  void _discardFetchedModels() {
    if (_fetchedModels.isEmpty &&
        _modelsError == null &&
        _modelsInfo == null) {
      return;
    }
    setState(() {
      _fetchedModels = [];
      _fetchedImageModels = [];
      _modelsError = null;
      _modelsInfo = null;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _imageModelController.dispose();
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
                      isExpanded: true,
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
                      // 付けないと「Gemini API (Imagen 3)」が枠から溢れる
                      isExpanded: true,
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
                              onChanged: (_) => _discardFetchedModels(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildRow(
                            context,
                            label: l.settingsModelLabel,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _modelInput(
                                    options: _fetchedModels,
                                    selected: _selectedModel,
                                    controller: _modelController,
                                    hint: 'gemini-2.5-flash',
                                    onSelected: (v) => setState(() {
                                      _selectedModel = v;
                                      if (v != 'custom') {
                                        _modelController.text = v;
                                      }
                                    }),
                                  ),
                                ),
                                _loadingModels
                                    ? const Padding(
                                        padding: EdgeInsets.only(left: 8),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.refresh),
                                        tooltip: l.settingsFetchModels,
                                        onPressed: _fetchModels,
                                      ),
                              ],
                            ),
                          ),
                          if (_fetchedModels.isNotEmpty &&
                              _selectedModel == 'custom') ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(left: 128),
                              child: TextField(
                                controller: _modelController,
                                decoration: _inputDecoration().copyWith(
                                  hintText: 'gemini-2.5-flash',
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildRow(
                            context,
                            label: l.settingsImageModelLabel,
                            child: _modelInput(
                              options: _fetchedImageModels,
                              selected: _selectedImageModel,
                              controller: _imageModelController,
                              hint: 'gemini-2.5-flash-image',
                              onSelected: (v) => setState(() {
                                _selectedImageModel = v;
                                if (v != 'custom') {
                                  _imageModelController.text = v;
                                }
                              }),
                            ),
                          ),
                          if (_fetchedImageModels.isNotEmpty &&
                              _selectedImageModel == 'custom') ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(left: 128),
                              child: TextField(
                                controller: _imageModelController,
                                decoration: _inputDecoration().copyWith(
                                  hintText: 'gemini-2.5-flash-image',
                                ),
                              ),
                            ),
                          ],
                          if (_modelsInfo != null) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 128),
                              child: Text(
                                _modelsInfo!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                          if (_modelsError != null) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 128),
                              child: Text(
                                _modelsError!,
                                style: TextStyle(
                                    fontSize: 12, color: scheme.error),
                              ),
                            ),
                          ],
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

  /// 一覧を取得済みならドロップダウン、未取得なら手入力欄
  Widget _modelInput({
    required List<String> options,
    required String selected,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onSelected,
  }) {
    if (options.isEmpty) {
      return TextField(
        controller: controller,
        decoration: _inputDecoration().copyWith(hintText: hint),
      );
    }
    return DropdownButtonFormField<String>(
      // 一覧や選択が入れ替わったら作り直す(initialValueの変化は反映されないため)
      key: ValueKey('${options.length}:${options.join(',')}|$selected'),
      initialValue: selected,
      isExpanded: true,
      decoration: _inputDecoration(),
      items: [
        ...options.map((m) => DropdownMenuItem(
              value: m,
              child: Text(m, overflow: TextOverflow.ellipsis),
            )),
        DropdownMenuItem(
          value: 'custom',
          child: Text(AppLocalizations.of(context).settingsModelCustom),
        ),
      ],
      onChanged: (v) {
        if (v != null) onSelected(v);
      },
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
