import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static final _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive',
      'email',
      'profile',
    ],
  );

  static GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<bool> trySignInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      return account != null;
    } catch (_) {
      return false;
    }
  }

  static String? lastError;

  Future<bool> signIn() async {
    try {
      lastError = null;
      final account = await _googleSignIn.signIn();
      return account != null;
    } catch (e, st) {
      lastError = '$e';
      // ignore: avoid_print
      print('SignIn error: $e\n$st');
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  Future<http.Client?> getAuthClient() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return null;

    final auth = await account.authentication;
    if (auth.accessToken == null) return null;

    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        auth.accessToken!,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      auth.idToken,
      ['https://www.googleapis.com/auth/drive'],
    );

    return authenticatedClient(http.Client(), credentials);
  }

  String get displayName =>
      _googleSignIn.currentUser?.displayName ?? '';

  String get email =>
      _googleSignIn.currentUser?.email ?? '';
}
