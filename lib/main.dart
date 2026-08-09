import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'screens/workspace_select_screen.dart';
import 'services/locale_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ManidocApp());
}

// ignore: library_private_types_in_public_api
class ManidocApp extends StatefulWidget {
  const ManidocApp({super.key});

  // ignore: library_private_types_in_public_api
  static _ManidocAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_ManidocAppState>();

  @override
  State<ManidocApp> createState() => _ManidocAppState();
}

class _ManidocAppState extends State<ManidocApp> {
  Locale? _locale;
  final _localeService = LocaleService();

  @override
  void initState() {
    super.initState();
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final locale = await _localeService.getLocale();
    if (locale != null) setState(() => _locale = locale);
  }

  void setLocale(Locale locale) {
    setState(() => _locale = locale);
    _localeService.setLocale(locale);
  }

  void clearLocale() {
    setState(() => _locale = null);
    _localeService.clearLocale();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manidoc Light',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja'),
        Locale('en'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const WorkspaceSelectScreen(),
    );
  }
}

