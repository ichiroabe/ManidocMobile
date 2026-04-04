import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/drive_service.dart';
import '../services/gemini_service.dart';
import '../models/workspace_info.dart';

class AiAgentScreen extends StatefulWidget {
  final WorkspaceInfo workspace;
  final VoidCallback? onProjectCreated;

  const AiAgentScreen({
    super.key,
    required this.workspace,
    this.onProjectCreated,
  });

  @override
  State<AiAgentScreen> createState() => _AiAgentScreenState();
}

class _AiAgentScreenState extends State<AiAgentScreen> {
  final _gemini = GeminiService();
  final _driveService = DriveService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];
  final List<(String, String)> _history = []; // (role, content)

  bool _useWebSearch = false;
  bool _mdMode = false;
  bool _sending = false;
  String? _lastMarkdownOutput;

  static const _systemPromptJa =
      '【Markdown出力フォーマット】\n'
      '# プロジェクト名（H1は1つのみ）\n'
      'プロジェクトの概要説明\n\n'
      '## セクション名\n'
      '本文内容（箇条書き・段落 どちらでも可）\n\n'
      '### サブセクション名\n'
      '本文内容\n\n'
      '> 補足コメント（引用ブロックはコメントボックスとして取り込まれます）\n\n'
      '【ルール】\n'
      '- H1は1つのみ（プロジェクト名として使用）\n'
      '- セクションは必ず ## 見出し（H2）で区切る\n'
      '- 見出しはH1→H2→H3の順で使う\n'
      '- 画像は含めない\n'
      '- Markdownはコードブロック（```）で囲まない';

  static const _systemPromptEn =
      '[Markdown Output Format]\n'
      '# Project Name (only one H1)\n'
      'Project overview\n\n'
      '## Section Name\n'
      'Body content (bullet points or paragraphs)\n\n'
      '### Subsection Name\n'
      'Body content\n\n'
      '> Supplementary comment (blockquotes are imported as comment boxes)\n\n'
      '[Rules]\n'
      '- Only one H1 (used as the project name)\n'
      '- Always separate sections with ## headings (H2)\n'
      '- Use headings in order: H1 → H2 → H3\n'
      '- Do not include images\n'
      '- Do not wrap Markdown in a code block (```)';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final l = AppLocalizations.of(context);
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: l.aiAgentGreeting));
      });
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _buildSystemPrompt(String languageCode) {
    return languageCode == 'ja' ? _systemPromptJa : _systemPromptEn;
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final apiKey = await _gemini.getApiKey();
    if (!mounted) return;
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).aiAgentNoApiKey)),
      );
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _sending = true;
      _lastMarkdownOutput = null;
    });
    _inputController.clear();
    _scrollToBottom();

    // Build API message (MD mode appends instruction)
    String apiMessage = text;
    if (_mdMode) {
      final lang = Localizations.localeOf(context).languageCode;
      if (lang == 'ja') {
        apiMessage += '\n\n以下のMarkdown形式で出力してください。\n'
            '# タイトル（1つだけ）\n概要\n\n## セクション名\n本文\n\n'
            'Markdownのみ出力し、前後の説明文や```は不要です。';
      } else {
        apiMessage += '\n\nPlease output in the following Markdown format.\n'
            '# Title (only one)\nOverview\n\n## Section Name\nBody\n\n'
            'Output Markdown only, without surrounding explanations or ``` blocks.';
      }
    }
    _history.add(('user', apiMessage));

    // Build full prompt with system + history
    final lang = Localizations.localeOf(context).languageCode;
    final systemPrompt = _buildSystemPrompt(lang);
    final promptParts = <String>[systemPrompt, ''];
    for (final (role, content) in _history) {
      promptParts.add('${role == 'user' ? 'User' : 'Assistant'}: $content');
    }
    final fullPrompt = promptParts.join('\n');

    try {
      String? response;
      if (_useWebSearch) {
        response = await _gemini.generateWithGrounding(fullPrompt);
      } else {
        response = await _gemini.generate(fullPrompt);
      }

      if (!mounted) return;
      final aiText = response ?? AppLocalizations.of(context).aiAgentError;

      // Strip search sources from history
      String historyContent = aiText;
      final srcIdx = aiText.indexOf('\n\n---\n**検索ソース:**');
      if (srcIdx >= 0) historyContent = aiText.substring(0, srcIdx);
      _history.add(('assistant', historyContent));

      String? markdownOutput;
      if (_isMarkdownOutput(aiText)) {
        markdownOutput = _extractMarkdown(aiText);
      }

      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: aiText));
        _lastMarkdownOutput = markdownOutput;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
            role: 'assistant',
            content: '⚠ ${_friendlyError(e)}'));
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('429') || s.contains('RESOURCE_EXHAUSTED') || s.contains('quota')) {
      final delay = RegExp(r'"retryDelay":\s*"(\d+)s"').firstMatch(s);
      final wait = delay != null ? '約${delay.group(1)}秒後に再試行してください。' : 'しばらく待ってから再試行してください。';
      return 'リクエスト制限に達しました（無料枠の上限）。$wait';
    }
    if (s.contains('403') || s.contains('API_KEY') || s.contains('PERMISSION_DENIED')) {
      return 'APIキーが無効です。設定画面で確認してください。';
    }
    if (s.contains('404') || s.contains('NOT_FOUND')) {
      return 'モデルが見つかりません。設定画面でモデル名を確認してください。';
    }
    if (s.contains('SocketException') || s.contains('network') || s.contains('connection')) {
      return 'ネットワークエラー。インターネット接続を確認してください。';
    }
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  bool _isMarkdownOutput(String text) {
    final hasH1 = RegExp(r'^# .+', multiLine: true).hasMatch(text);
    final hasH2 = RegExp(r'^## .+', multiLine: true).hasMatch(text);
    return hasH1 && hasH2;
  }

  String _extractMarkdown(String text) {
    // Remove code block wrapper if present
    final codeBlock = RegExp(
      r'^```(?:markdown|md)?\r?\n([\s\S]*?)\r?\n```\s*$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(text);
    if (codeBlock != null) return codeBlock.group(1)!.trim();

    final h1 = RegExp(r'^# .+', multiLine: true).firstMatch(text);
    if (h1 != null) return text.substring(h1.start).trim();

    return text.trim();
  }

  Future<void> _createProjectFromMarkdown() async {
    final markdown = _lastMarkdownOutput;
    if (markdown == null) return;

    final l = AppLocalizations.of(context);
    final project = _parseMarkdownToProject(markdown);

    setState(() => _sending = true);
    try {
      final fileId = await _driveService.createProject(
        project,
        widget.workspace.androidFolderId,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      if (fileId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l.aiAgentProjectCreated}: ${project.name}')),
        );
        setState(() => _lastMarkdownOutput = null);
        widget.onProjectCreated?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  ManidocProject _parseMarkdownToProject(String markdown) {
    final lines = markdown.split('\n');
    String projectName = 'AI Project';
    String projectDesc = '';
    final rootNodes = <ManidocNode>[];

    ManidocNode? currentH2;
    ManidocNode? currentH3;
    final bodyLines = <String>[];

    void flushBody(ManidocNode? node) {
      if (node == null) return;
      final body = bodyLines.join('\n').trim();
      if (body.isNotEmpty) node.article = body;
      bodyLines.clear();
    }

    for (final line in lines) {
      if (line.startsWith('# ') && !line.startsWith('## ')) {
        projectName = line.substring(2).trim();
      } else if (line.startsWith('## ')) {
        flushBody(currentH3 ?? currentH2);
        currentH3 = null;
        final node = ManidocNode.create(line.substring(3).trim());
        rootNodes.add(node);
        currentH2 = node;
        bodyLines.clear();
      } else if (line.startsWith('### ')) {
        flushBody(currentH3 ?? currentH2);
        currentH3 = null;
        if (currentH2 != null) {
          final node = ManidocNode.create(line.substring(4).trim());
          currentH2.children.add(node);
          currentH3 = node;
        }
        bodyLines.clear();
      } else if (line.startsWith('> ')) {
        // blockquote → comment of current node
        final target = currentH3 ?? currentH2;
        if (target != null) {
          final comment = line.substring(2).trim();
          target.comment = target.comment.isEmpty
              ? comment
              : '${target.comment}\n$comment';
        }
      } else {
        if (currentH2 == null) {
          // before first H2: project description
          if (line.isNotEmpty) projectDesc += '$line\n';
        } else {
          bodyLines.add(line);
        }
      }
    }
    flushBody(currentH3 ?? currentH2);

    return ManidocProject(
      id: const Uuid().v4(),
      name: projectName,
      description: projectDesc.trim(),
      rootNodes: rootNodes,
    );
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _history.clear();
      _lastMarkdownOutput = null;
      final l = AppLocalizations.of(context);
      _messages.add(_ChatMessage(role: 'assistant', content: l.aiAgentGreeting));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.aiAgent),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l.aiAgentClear,
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          // Toggle bar
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                FilterChip(
                  label: Text(l.aiAgentWebSearch),
                  selected: _useWebSearch,
                  onSelected: (v) {
                    setState(() => _useWebSearch = v);
                    final msg = v
                        ? l.aiAgentWebSearchOn
                        : l.aiAgentWebSearchOff;
                    setState(() => _messages
                        .add(_ChatMessage(role: 'assistant', content: msg)));
                    _scrollToBottom();
                  },
                  avatar: const Icon(Icons.search, size: 16),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l.aiAgentMdMode),
                  selected: _mdMode,
                  onSelected: (v) => setState(() => _mdMode = v),
                  avatar: const Icon(Icons.article_outlined, size: 16),
                ),
              ],
            ),
          ),

          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (_sending && i == _messages.length) {
                  return _buildThinkingBubble(l);
                }
                return _buildBubble(_messages[i]);
              },
            ),
          ),

          // Create project button
          if (_lastMarkdownOutput != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: FilledButton.icon(
                onPressed: _sending ? null : _createProjectFromMarkdown,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(l.aiAgentCreateProject),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),

          // Input area
          Padding(
            padding: EdgeInsets.fromLTRB(
                8, 8, 8, MediaQuery.of(context).viewInsets.bottom + 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l.aiAgentInputHint,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    minimumSize: Size.zero,
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          msg.content,
          style: TextStyle(
            color: isUser
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildThinkingBubble(AppLocalizations l) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(l.aiAgentThinking),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String content;

  _ChatMessage({required this.role, required this.content});
}
