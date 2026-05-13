import 'package:google_sign_in/google_sign_in.dart';
import 'app_logger.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _kDriveScope = 'https://www.googleapis.com/auth/drive.file';

  final _googleSignIn = GoogleSignIn(
    scopes: ['email', _kDriveScope],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      final user = await _googleSignIn.signInSilently();
      if (user == null) return null;
      // On Android, Play Services may restore a session whose cached
      // authorization lacked drive.file. A null accessToken exposes this.
      // Return null so the user is prompted to sign in interactively.
      final auth = await user.authentication;
      if (auth.accessToken == null) return null;
      return user;
    } catch (e) {
      AppLogger.instance.warn('AuthService', 'silent sign-in failed', e);
      return null;
    }
  }

  // Throws on error so callers can surface the message to the user.
  Future<GoogleSignInAccount?> signIn() async {
    // signOut clears the local credential cache. We intentionally skip
    // disconnect() here: it revokes the server-side grant, and on Android
    // Play Services can silently hand back a cached (now-revoked) token on the
    // subsequent signIn(), causing an immediate 401 from the Drive API.
    await _googleSignIn.signOut().catchError((_) => null);
    final user = await _googleSignIn.signIn();
    if (user == null) return null;
    return await _ensureDriveScope(user);
  }

  // Request drive.file explicitly and verify a valid access token is returned.
  Future<GoogleSignInAccount> _ensureDriveScope(
      GoogleSignInAccount user) async {
    final granted = await _googleSignIn.requestScopes([_kDriveScope]);
    if (!granted) {
      throw 'Google Drive access is required for notes sync. '
          'Please grant Drive permission and try again.';
    }
    final current = _googleSignIn.currentUser ?? user;
    // Verify the token actually exists after the scope grant.
    final auth = await current.authentication;
    if (auth.accessToken == null) {
      AppLogger.instance.warn(
          'AuthService', 'access token is null after scope grant');
      throw 'Failed to obtain a valid Drive access token. '
          'Please try signing in again.';
    }
    return current;
  }

  Future<void> signOut() => _googleSignIn.signOut();

  Future<Map<String, String>?> getAuthHeaders() async {
    final user = _googleSignIn.currentUser;
    if (user == null) return null;
    try {
      final auth = await user.authentication;
      final token = auth.accessToken;
      if (token == null) {
        AppLogger.instance.warn('AuthService', 'null access token in getAuthHeaders');
        return null;
      }
      return {'Authorization': 'Bearer $token'};
    } catch (e) {
      AppLogger.instance.warn('AuthService', 'getAuthHeaders failed', e);
      return null;
    }
  }
}
