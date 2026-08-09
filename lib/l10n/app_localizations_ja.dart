// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Manidoc';

  @override
  String get settings => '設定';

  @override
  String get account => 'アカウント';

  @override
  String get signOut => 'サインアウト';

  @override
  String get signIn => 'Googleでサインイン';

  @override
  String get signInFailed => 'サインインに失敗しました';

  @override
  String get workspace => 'ワークスペース';

  @override
  String get addWorkspace => '追加';

  @override
  String get addWorkspaceTitle => 'ワークスペースを追加';

  @override
  String get noWorkspace => 'ワークスペースがありません';

  @override
  String get addWorkspaceButton => '追加する';

  @override
  String get deleteWorkspace => '削除確認';

  @override
  String deleteWorkspaceMessage(String name) {
    return '「$name」を削除しますか？\n（Google Drive 上のデータは削除されません）';
  }

  @override
  String get windowsFolder => 'Windowsフォルダ（読み取り専用）';

  @override
  String get androidFolder => 'Androidフォルダ（読み書き）';

  @override
  String get androidFolderHint =>
      '※ 未選択の場合、Windowsフォルダ内に _android フォルダを自動作成します';

  @override
  String get selectFolder => 'フォルダを選ぶ';

  @override
  String get myDrive => 'マイドライブ';

  @override
  String get noFolder => 'フォルダがありません';

  @override
  String get newFolder => '新しいフォルダ';

  @override
  String get newFolderName => 'フォルダ名';

  @override
  String get createFolder => '作成';

  @override
  String get windowsTab => 'Windows';

  @override
  String get androidTab => 'Android';

  @override
  String get noProject => 'プロジェクトがありません';

  @override
  String get noProjectAndroid => 'まだプロジェクトがありません';

  @override
  String get createProjectButton => '作成する';

  @override
  String get newProject => '新規プロジェクト';

  @override
  String get newProjectFab => '新規プロジェクト';

  @override
  String get projectName => 'プロジェクト名';

  @override
  String get renameProject => '名前を変更';

  @override
  String get deleteProject => '削除';

  @override
  String deleteProjectMessage(String name) {
    return '「$name」を削除しますか？\n（Google Drive上のファイルも削除されます）';
  }

  @override
  String get readOnly => '読み取り専用';

  @override
  String get addNode => 'ルートノードを追加';

  @override
  String get addNodeTitle => 'ノードを追加';

  @override
  String get nodeTitle => 'タイトル';

  @override
  String get noNode => 'ノードがありません';

  @override
  String get addNodeButton => 'ノードを追加';

  @override
  String get addChildNode => '子ノードを追加';

  @override
  String get deleteNode => '削除';

  @override
  String get deleteNodeTitle => '削除確認';

  @override
  String deleteNodeMessage(String title) {
    return '「$title」を削除しますか？\n子ノードも全て削除されます。';
  }

  @override
  String get save => '保存';

  @override
  String get cancel => 'キャンセル';

  @override
  String get add => '追加';

  @override
  String get delete => '削除';

  @override
  String get change => '変更';

  @override
  String get execute => '実行';

  @override
  String get search => '検索';

  @override
  String get close => '閉じる';

  @override
  String get aiAssistant => 'AIアシスタント';

  @override
  String get aiContinue => '続きを書く';

  @override
  String get aiSummarize => '要約する';

  @override
  String get aiRefine => '改善する';

  @override
  String get aiWebSearch => 'Web検索して回答';

  @override
  String get aiSearchHint => '検索クエリ・質問を入力';

  @override
  String get aiCustom => 'カスタム指示';

  @override
  String get aiCustomHint => 'カスタム指示を入力';

  @override
  String get aiInsert => '本文に追加';

  @override
  String get geminiApiKey => 'Gemini API キー';

  @override
  String get geminiApiKeyHint => 'Google AI Studio から取得してください';

  @override
  String get apiKeyLabel => 'APIキー';

  @override
  String get geminiModel => 'モデル名';

  @override
  String get apiKeySaved => '設定を保存しました';

  @override
  String get language => '言語';

  @override
  String get languageJa => '日本語';

  @override
  String get languageEn => 'English';

  @override
  String get aiAgent => 'AIエージェント';

  @override
  String get aiAgentTab => 'AIエージェント';

  @override
  String get aiAgentGreeting => 'こんにちは！プロジェクトの構成を一緒に考えましょう。どんなドキュメントを作りたいですか？';

  @override
  String get aiAgentInputHint => 'メッセージを入力...';

  @override
  String get aiAgentThinking => '考え中...';

  @override
  String get aiAgentError => 'エラーが発生しました';

  @override
  String get aiAgentNoApiKey => 'Gemini APIキーが設定されていません。設定画面から入力してください。';

  @override
  String get aiAgentWebSearch => 'Web検索';

  @override
  String get aiAgentWebSearchOn => '🔍 Web検索が有効になりました';

  @override
  String get aiAgentWebSearchOff => 'Web検索が無効になりました';

  @override
  String get aiAgentMdMode => 'Markdown出力';

  @override
  String get aiAgentClear => 'チャットをクリア';

  @override
  String get aiAgentCreateProject => 'このMarkdownからプロジェクトを作成';

  @override
  String get aiAgentProjectCreated => 'プロジェクトを作成しました';

  @override
  String get aiAgentModelTitle => '使用するモデル';

  @override
  String get aiAgentModelRefresh => '一覧を取り直す';

  @override
  String get aiAgentModelEmpty => 'モデル一覧がありません。設定画面でAPIキーを確認してください。';

  @override
  String aiAgentModelChanged(String model) {
    return 'モデルを $model に変更しました';
  }

  @override
  String get settingsSectionAi => '画像生成 / アシスタント設定';

  @override
  String get settingsLanguageLabel => '言語 (Language):';

  @override
  String get settingsProviderLabel => 'AIプロバイダ:';

  @override
  String get settingsApiKeyLabel => 'API キー:';

  @override
  String get settingsModelLabel => 'モデル名:';

  @override
  String get settingsImageModelLabel => '画像モデル名:';

  @override
  String get settingsFetchModels => 'APIキーで使えるモデル一覧を取得';

  @override
  String get settingsModelCustom => 'カスタム (手入力)';

  @override
  String settingsModelsFetched(int text, int image) {
    return 'テキスト$text件 / 画像$image件を取得しました';
  }

  @override
  String get settingsModelsFetchFailed =>
      'モデル一覧を取得できませんでした。APIキーと通信状況を確認してください。';

  @override
  String get settingsModelListLink => '利用可能なモデル名を確認する';

  @override
  String get settingsEndpointLabel => 'エンドポイント:';

  @override
  String get settingsApiKeyHint => 'APIキーは Google AI Studio から取得してください。';
}
