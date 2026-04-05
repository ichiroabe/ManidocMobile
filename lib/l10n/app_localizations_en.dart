// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Manidoc';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signIn => 'Sign in with Google';

  @override
  String get signInFailed => 'Sign-in failed';

  @override
  String get workspace => 'Workspace';

  @override
  String get addWorkspace => 'Add';

  @override
  String get addWorkspaceTitle => 'Add Workspace';

  @override
  String get noWorkspace => 'No workspaces';

  @override
  String get addWorkspaceButton => 'Add workspace';

  @override
  String get deleteWorkspace => 'Delete';

  @override
  String deleteWorkspaceMessage(String name) {
    return 'Delete \"$name\"?\n(Data on Google Drive will not be deleted)';
  }

  @override
  String get windowsFolder => 'Windows folder (read-only)';

  @override
  String get androidFolder => 'Android folder (read-write)';

  @override
  String get androidFolderHint =>
      '※ If not selected, an _android folder will be created automatically inside the Windows folder.';

  @override
  String get selectFolder => 'Select folder';

  @override
  String get myDrive => 'My Drive';

  @override
  String get noFolder => 'No folders';

  @override
  String get newFolder => 'New folder';

  @override
  String get newFolderName => 'Folder name';

  @override
  String get createFolder => 'Create';

  @override
  String get windowsTab => 'Windows';

  @override
  String get androidTab => 'Android';

  @override
  String get noProject => 'No projects';

  @override
  String get noProjectAndroid => 'No projects yet';

  @override
  String get createProjectButton => 'Create';

  @override
  String get newProject => 'New Project';

  @override
  String get newProjectFab => 'New Project';

  @override
  String get projectName => 'Project name';

  @override
  String get renameProject => 'Rename';

  @override
  String get deleteProject => 'Delete';

  @override
  String deleteProjectMessage(String name) {
    return 'Delete \"$name\"?\n(The file on Google Drive will also be deleted)';
  }

  @override
  String get readOnly => 'Read only';

  @override
  String get addNode => 'Add root node';

  @override
  String get addNodeTitle => 'Add node';

  @override
  String get nodeTitle => 'Title';

  @override
  String get noNode => 'No nodes';

  @override
  String get addNodeButton => 'Add node';

  @override
  String get addChildNode => 'Add child node';

  @override
  String get deleteNode => 'Delete';

  @override
  String get deleteNodeTitle => 'Delete';

  @override
  String deleteNodeMessage(String title) {
    return 'Delete \"$title\"?\nAll child nodes will also be deleted.';
  }

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get add => 'Add';

  @override
  String get delete => 'Delete';

  @override
  String get change => 'Change';

  @override
  String get execute => 'Execute';

  @override
  String get search => 'Search';

  @override
  String get close => 'Close';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get aiContinue => 'Continue writing';

  @override
  String get aiSummarize => 'Summarize';

  @override
  String get aiRefine => 'Improve';

  @override
  String get aiWebSearch => 'Search & Answer';

  @override
  String get aiSearchHint => 'Enter search query or question';

  @override
  String get aiCustom => 'Custom instruction';

  @override
  String get aiCustomHint => 'Enter custom instruction';

  @override
  String get aiInsert => 'Insert into article';

  @override
  String get geminiApiKey => 'Gemini API Key';

  @override
  String get geminiApiKeyHint => 'Get it from Google AI Studio';

  @override
  String get apiKeyLabel => 'API Key';

  @override
  String get geminiModel => 'Model name';

  @override
  String get apiKeySaved => 'Settings saved';

  @override
  String get language => 'Language';

  @override
  String get languageJa => '日本語';

  @override
  String get languageEn => 'English';

  @override
  String get aiAgent => 'AI Agent';

  @override
  String get aiAgentTab => 'AI Agent';

  @override
  String get aiAgentGreeting =>
      'Hello! Let\'s plan your project together. What kind of document would you like to create?';

  @override
  String get aiAgentInputHint => 'Type a message...';

  @override
  String get aiAgentThinking => 'Thinking...';

  @override
  String get aiAgentError => 'An error occurred';

  @override
  String get aiAgentNoApiKey =>
      'Gemini API key is not set. Please enter it in Settings.';

  @override
  String get aiAgentWebSearch => 'Web Search';

  @override
  String get aiAgentWebSearchOn => '🔍 Web search enabled';

  @override
  String get aiAgentWebSearchOff => 'Web search disabled';

  @override
  String get aiAgentMdMode => 'Markdown output';

  @override
  String get aiAgentClear => 'Clear chat';

  @override
  String get aiAgentCreateProject => 'Create project from this Markdown';

  @override
  String get aiAgentProjectCreated => 'Project created';

  @override
  String get settingsSectionAi => 'Image generation / Assistant';

  @override
  String get settingsLanguageLabel => 'Language:';

  @override
  String get settingsProviderLabel => 'AI Provider:';

  @override
  String get settingsApiKeyLabel => 'API Key:';

  @override
  String get settingsModelLabel => 'Model name:';

  @override
  String get settingsModelListLink => 'View available model names';

  @override
  String get settingsEndpointLabel => 'Endpoint:';

  @override
  String get settingsApiKeyHint => 'Get your API key from Google AI Studio.';
}
