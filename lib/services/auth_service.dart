import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
      debugPrint('[AuthService] silent sign-in failed: $e');
      return null;
    }
  }

  // Throws on error so callers can surface the message to the user.
  Future<GoogleSignInAccount?> signIn() async {
    // signOut clears the local credential cache; disconnect revokes server-side.
    // Both are fire-and-forget — errors are non-fatal.
    await _googleSignIn.signOut().catchError((_) => null);
    await _googleSignIn.disconnect().catchError((_) => null);
    final user = await _googleSignIn.signIn();
    if (user == null) return null;
    return await _ensureDriveScope(user);
  }

  // On Android, Play Services may silently reuse a previous authorization that
  // lacked drive.file scope, returning a null accessToken. Detect this and
  // request the scope explicitly so Drive API calls succeed.
  Future<GoogleSignInAccount> _ensureDriveScope(
      GoogleSignInAccount user) async {
    try {
      final auth = await user.authentication;
      if (auth.accessToken != null) return user;
    } catch (_) {
      return user; // Can't verify — proceed and let Drive calls surface errors.
    }
    final granted = await _googleSignIn.requestScopes([_kDriveScope]);
    if (!granted) {
      throw 'Google Drive access is required for notes sync. '
          'Please grant Drive permission and try again.';
    }
    // currentUser holds a fresh token after the scope grant.
    return _googleSignIn.currentUser ?? user;
  }

  Future<void> signOut() => _googleSignIn.signOut();

  Future<Map<String, String>?> getAuthHeaders() async {
    final user = _googleSignIn.currentUser;
    if (user == null) return null;
    return user.authHeaders;
  }
}
