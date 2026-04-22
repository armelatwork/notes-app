import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (_) {
      return null;
    }
  }

  // Throws on error so callers can surface the message to the user.
  Future<GoogleSignInAccount?> signIn() async {
    // Disconnect any stale session so the account picker always appears.
    await _googleSignIn.disconnect().catchError((_) => null);
    return await _googleSignIn.signIn();
  }

  Future<void> signOut() => _googleSignIn.signOut();

  Future<Map<String, String>?> getAuthHeaders() async {
    final user = _googleSignIn.currentUser;
    if (user == null) return null;
    return user.authHeaders;
  }
}
