import 'package:firebase_auth/firebase_auth.dart';
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
      await _signInToFirebase(auth);
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
    final ensured = await _ensureDriveScope(user);
    await _signInToFirebase(await ensured.authentication);
    return ensured;
  }

  Future<void> _signInToFirebase(GoogleSignInAuthentication auth) async {
    try {
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      AppLogger.instance.warn('AuthService', 'Firebase sign-in failed', e);
    }
  }

  // Verify the access token is valid after sign-in.
  // drive.file is already declared in the GoogleSignIn constructor scopes so
  // calling requestScopes() again is redundant and triggers a second OAuth
  // popup on macOS. We only need to confirm the token was actually issued.
  Future<GoogleSignInAccount> _ensureDriveScope(
      GoogleSignInAccount user) async {
    final current = _googleSignIn.currentUser ?? user;
    final auth = await current.authentication;
    if (auth.accessToken == null) {
      throw 'Google Drive access is required for notes sync. '
          'Please grant Drive permission and try again.';
    }
    return current;
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await _googleSignIn.signOut();
  }

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
