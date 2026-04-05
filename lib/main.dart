import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/workspace_select_screen.dart';
import 'services/auth_service.dart';
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
      home: Platform.isWindows
          ? const WorkspaceSelectScreen()
          : const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSignIn();
  }

  Future<void> _checkSignIn() async {
    final auth = AuthService();
    final signedIn = await auth.trySignInSilently();
    setState(() {
      _signedIn = signedIn;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _signedIn ? const WorkspaceSelectScreen() : const LoginScreen();
  }
}
