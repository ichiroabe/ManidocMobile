import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'Manidoc'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get settings;

  /// No description provided for @account.
  ///
  /// In ja, this message translates to:
  /// **'アカウント'**
  String get account;

  /// No description provided for @signOut.
  ///
  /// In ja, this message translates to:
  /// **'サインアウト'**
  String get signOut;

  /// No description provided for @signIn.
  ///
  /// In ja, this message translates to:
  /// **'Googleでサインイン'**
  String get signIn;

  /// No description provided for @signInFailed.
  ///
  /// In ja, this message translates to:
  /// **'サインインに失敗しました'**
  String get signInFailed;

  /// No description provided for @workspace.
  ///
  /// In ja, this message translates to:
  /// **'ワークスペース'**
  String get workspace;

  /// No description provided for @addWorkspace.
  ///
  /// In ja, this message translates to:
  /// **'追加'**
  String get addWorkspace;

  /// No description provided for @addWorkspaceTitle.
  ///
  /// In ja, this message translates to:
  /// **'ワークスペースを追加'**
  String get addWorkspaceTitle;

  /// No description provided for @noWorkspace.
  ///
  /// In ja, this message translates to:
  /// **'ワークスペースがありません'**
  String get noWorkspace;

  /// No description provided for @addWorkspaceButton.
  ///
  /// In ja, this message translates to:
  /// **'追加する'**
  String get addWorkspaceButton;

  /// No description provided for @deleteWorkspace.
  ///
  /// In ja, this message translates to:
  /// **'削除確認'**
  String get deleteWorkspace;

  /// No description provided for @deleteWorkspaceMessage.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を削除しますか？\n（Google Drive 上のデータは削除されません）'**
  String deleteWorkspaceMessage(String name);

  /// No description provided for @windowsFolder.
  ///
  /// In ja, this message translates to:
  /// **'Windowsフォルダ（読み取り専用）'**
  String get windowsFolder;

  /// No description provided for @androidFolder.
  ///
  /// In ja, this message translates to:
  /// **'Androidフォルダ（読み書き）'**
  String get androidFolder;

  /// No description provided for @androidFolderHint.
  ///
  /// In ja, this message translates to:
  /// **'※ 未選択の場合、Windowsフォルダ内に _android フォルダを自動作成します'**
  String get androidFolderHint;

  /// No description provided for @selectFolder.
  ///
  /// In ja, this message translates to:
  /// **'フォルダを選ぶ'**
  String get selectFolder;

  /// No description provided for @myDrive.
  ///
  /// In ja, this message translates to:
  /// **'マイドライブ'**
  String get myDrive;

  /// No description provided for @noFolder.
  ///
  /// In ja, this message translates to:
  /// **'フォルダがありません'**
  String get noFolder;

  /// No description provided for @newFolder.
  ///
  /// In ja, this message translates to:
  /// **'新しいフォルダ'**
  String get newFolder;

  /// No description provided for @newFolderName.
  ///
  /// In ja, this message translates to:
  /// **'フォルダ名'**
  String get newFolderName;

  /// No description provided for @createFolder.
  ///
  /// In ja, this message translates to:
  /// **'作成'**
  String get createFolder;

  /// No description provided for @windowsTab.
  ///
  /// In ja, this message translates to:
  /// **'Windows'**
  String get windowsTab;

  /// No description provided for @androidTab.
  ///
  /// In ja, this message translates to:
  /// **'Android'**
  String get androidTab;

  /// No description provided for @noProject.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトがありません'**
  String get noProject;

  /// No description provided for @noProjectAndroid.
  ///
  /// In ja, this message translates to:
  /// **'まだプロジェクトがありません'**
  String get noProjectAndroid;

  /// No description provided for @createProjectButton.
  ///
  /// In ja, this message translates to:
  /// **'作成する'**
  String get createProjectButton;

  /// No description provided for @newProject.
  ///
  /// In ja, this message translates to:
  /// **'新規プロジェクト'**
  String get newProject;

  /// No description provided for @newProjectFab.
  ///
  /// In ja, this message translates to:
  /// **'新規プロジェクト'**
  String get newProjectFab;

  /// No description provided for @projectName.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクト名'**
  String get projectName;

  /// No description provided for @renameProject.
  ///
  /// In ja, this message translates to:
  /// **'名前を変更'**
  String get renameProject;

  /// No description provided for @deleteProject.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get deleteProject;

  /// No description provided for @deleteProjectMessage.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を削除しますか？\n（Google Drive上のファイルも削除されます）'**
  String deleteProjectMessage(String name);

  /// No description provided for @readOnly.
  ///
  /// In ja, this message translates to:
  /// **'読み取り専用'**
  String get readOnly;

  /// No description provided for @addNode.
  ///
  /// In ja, this message translates to:
  /// **'ルートノードを追加'**
  String get addNode;

  /// No description provided for @addNodeTitle.
  ///
  /// In ja, this message translates to:
  /// **'ノードを追加'**
  String get addNodeTitle;

  /// No description provided for @nodeTitle.
  ///
  /// In ja, this message translates to:
  /// **'タイトル'**
  String get nodeTitle;

  /// No description provided for @noNode.
  ///
  /// In ja, this message translates to:
  /// **'ノードがありません'**
  String get noNode;

  /// No description provided for @addNodeButton.
  ///
  /// In ja, this message translates to:
  /// **'ノードを追加'**
  String get addNodeButton;

  /// No description provided for @addChildNode.
  ///
  /// In ja, this message translates to:
  /// **'子ノードを追加'**
  String get addChildNode;

  /// No description provided for @deleteNode.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get deleteNode;

  /// No description provided for @deleteNodeTitle.
  ///
  /// In ja, this message translates to:
  /// **'削除確認'**
  String get deleteNodeTitle;

  /// No description provided for @deleteNodeMessage.
  ///
  /// In ja, this message translates to:
  /// **'「{title}」を削除しますか？\n子ノードも全て削除されます。'**
  String deleteNodeMessage(String title);

  /// No description provided for @save.
  ///
  /// In ja, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @add.
  ///
  /// In ja, this message translates to:
  /// **'追加'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get delete;

  /// No description provided for @change.
  ///
  /// In ja, this message translates to:
  /// **'変更'**
  String get change;

  /// No description provided for @execute.
  ///
  /// In ja, this message translates to:
  /// **'実行'**
  String get execute;

  /// No description provided for @search.
  ///
  /// In ja, this message translates to:
  /// **'検索'**
  String get search;

  /// No description provided for @close.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get close;

  /// No description provided for @aiAssistant.
  ///
  /// In ja, this message translates to:
  /// **'AIアシスタント'**
  String get aiAssistant;

  /// No description provided for @aiContinue.
  ///
  /// In ja, this message translates to:
  /// **'続きを書く'**
  String get aiContinue;

  /// No description provided for @aiSummarize.
  ///
  /// In ja, this message translates to:
  /// **'要約する'**
  String get aiSummarize;

  /// No description provided for @aiRefine.
  ///
  /// In ja, this message translates to:
  /// **'改善する'**
  String get aiRefine;

  /// No description provided for @aiWebSearch.
  ///
  /// In ja, this message translates to:
  /// **'Web検索して回答'**
  String get aiWebSearch;

  /// No description provided for @aiSearchHint.
  ///
  /// In ja, this message translates to:
  /// **'検索クエリ・質問を入力'**
  String get aiSearchHint;

  /// No description provided for @aiCustom.
  ///
  /// In ja, this message translates to:
  /// **'カスタム指示'**
  String get aiCustom;

  /// No description provided for @aiCustomHint.
  ///
  /// In ja, this message translates to:
  /// **'カスタム指示を入力'**
  String get aiCustomHint;

  /// No description provided for @aiInsert.
  ///
  /// In ja, this message translates to:
  /// **'本文に追加'**
  String get aiInsert;

  /// No description provided for @geminiApiKey.
  ///
  /// In ja, this message translates to:
  /// **'Gemini API キー'**
  String get geminiApiKey;

  /// No description provided for @geminiApiKeyHint.
  ///
  /// In ja, this message translates to:
  /// **'Google AI Studio から取得してください'**
  String get geminiApiKeyHint;

  /// No description provided for @apiKeyLabel.
  ///
  /// In ja, this message translates to:
  /// **'APIキー'**
  String get apiKeyLabel;

  /// No description provided for @geminiModel.
  ///
  /// In ja, this message translates to:
  /// **'モデル名'**
  String get geminiModel;

  /// No description provided for @apiKeySaved.
  ///
  /// In ja, this message translates to:
  /// **'設定を保存しました'**
  String get apiKeySaved;

  /// No description provided for @language.
  ///
  /// In ja, this message translates to:
  /// **'言語'**
  String get language;

  /// No description provided for @languageJa.
  ///
  /// In ja, this message translates to:
  /// **'日本語'**
  String get languageJa;

  /// No description provided for @languageEn.
  ///
  /// In ja, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @aiAgent.
  ///
  /// In ja, this message translates to:
  /// **'AIエージェント'**
  String get aiAgent;

  /// No description provided for @aiAgentTab.
  ///
  /// In ja, this message translates to:
  /// **'AIエージェント'**
  String get aiAgentTab;

  /// No description provided for @aiAgentGreeting.
  ///
  /// In ja, this message translates to:
  /// **'こんにちは！プロジェクトの構成を一緒に考えましょう。どんなドキュメントを作りたいですか？'**
  String get aiAgentGreeting;

  /// No description provided for @aiAgentInputHint.
  ///
  /// In ja, this message translates to:
  /// **'メッセージを入力...'**
  String get aiAgentInputHint;

  /// No description provided for @aiAgentThinking.
  ///
  /// In ja, this message translates to:
  /// **'考え中...'**
  String get aiAgentThinking;

  /// No description provided for @aiAgentError.
  ///
  /// In ja, this message translates to:
  /// **'エラーが発生しました'**
  String get aiAgentError;

  /// No description provided for @aiAgentNoApiKey.
  ///
  /// In ja, this message translates to:
  /// **'Gemini APIキーが設定されていません。設定画面から入力してください。'**
  String get aiAgentNoApiKey;

  /// No description provided for @aiAgentWebSearch.
  ///
  /// In ja, this message translates to:
  /// **'Web検索'**
  String get aiAgentWebSearch;

  /// No description provided for @aiAgentWebSearchOn.
  ///
  /// In ja, this message translates to:
  /// **'🔍 Web検索が有効になりました'**
  String get aiAgentWebSearchOn;

  /// No description provided for @aiAgentWebSearchOff.
  ///
  /// In ja, this message translates to:
  /// **'Web検索が無効になりました'**
  String get aiAgentWebSearchOff;

  /// No description provided for @aiAgentMdMode.
  ///
  /// In ja, this message translates to:
  /// **'Markdown出力'**
  String get aiAgentMdMode;

  /// No description provided for @aiAgentClear.
  ///
  /// In ja, this message translates to:
  /// **'チャットをクリア'**
  String get aiAgentClear;

  /// No description provided for @aiAgentCreateProject.
  ///
  /// In ja, this message translates to:
  /// **'このMarkdownからプロジェクトを作成'**
  String get aiAgentCreateProject;

  /// No description provided for @aiAgentProjectCreated.
  ///
  /// In ja, this message translates to:
  /// **'プロジェクトを作成しました'**
  String get aiAgentProjectCreated;

  /// No description provided for @settingsSectionAi.
  ///
  /// In ja, this message translates to:
  /// **'画像生成 / アシスタント設定'**
  String get settingsSectionAi;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In ja, this message translates to:
  /// **'言語 (Language):'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsProviderLabel.
  ///
  /// In ja, this message translates to:
  /// **'AIプロバイダ:'**
  String get settingsProviderLabel;

  /// No description provided for @settingsApiKeyLabel.
  ///
  /// In ja, this message translates to:
  /// **'API キー:'**
  String get settingsApiKeyLabel;

  /// No description provided for @settingsModelLabel.
  ///
  /// In ja, this message translates to:
  /// **'モデル名:'**
  String get settingsModelLabel;

  /// No description provided for @settingsModelListLink.
  ///
  /// In ja, this message translates to:
  /// **'利用可能なモデル名を確認する'**
  String get settingsModelListLink;

  /// No description provided for @settingsEndpointLabel.
  ///
  /// In ja, this message translates to:
  /// **'エンドポイント:'**
  String get settingsEndpointLabel;

  /// No description provided for @settingsApiKeyHint.
  ///
  /// In ja, this message translates to:
  /// **'APIキーは Google AI Studio から取得してください。'**
  String get settingsApiKeyHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
