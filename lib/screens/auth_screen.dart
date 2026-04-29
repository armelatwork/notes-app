import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../services/local_auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isCreatingAccount = false;
  bool _loading = false;
  String? _error;
  bool _hasLocalAccount = false;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLocalAccount();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkLocalAccount() async {
    final exists = await LocalAuthService.instance.accountExists();
    if (mounted) {
      setState(() {
        _hasLocalAccount = exists;
        _isCreatingAccount = !exists;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await AuthService.instance.signIn();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
      return;
    }
    if (!mounted) return;
    if (googleUser == null) {
      setState(() { _loading = false; _error = 'Sign-in cancelled.' ; });
      return;
    }
    await ref.read(appUserProvider.notifier).initGoogleEncryptionKey(googleUser.id);
    await ref.read(appUserProvider.notifier).setUser(AppUser(
      id: googleUser.id,
      displayName: googleUser.displayName ?? googleUser.email,
      email: googleUser.email,
      type: AuthType.google,
    ));
  }

  Future<void> _submitLocal() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    setState(() { _loading = true; _error = null; });

    AppUser? user;
    if (_isCreatingAccount) {
      user = await LocalAuthService.instance.createAccount(username, password);
      if (user == null) {
        setState(() {
          _loading = false;
          _error = 'An account already exists. Sign in instead.';
          _isCreatingAccount = false;
          _hasLocalAccount = true;
        });
        return;
      }
    } else {
      user = await LocalAuthService.instance.signIn(username, password);
      if (user == null) {
        setState(() { _loading = false; _error = 'Invalid username or password.'; });
        return;
      }
    }

    final keyBytes = await LocalAuthService.instance.deriveEncryptionKey(password);
    EncryptionService.instance.initWithKey(keyBytes);
    if (!mounted) return;
    await ref.read(appUserProvider.notifier).setUser(user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.note_alt_outlined, size: 72,
                    color: Color(0xFFFFD60A)),
                const SizedBox(height: 12),
                Text(
                  'Notes',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to create and access your notes',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),

                // Google
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),

                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[500])),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 24),

                Text(
                  _isCreatingAccount ? 'Create a local account' : 'Local account',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_loading,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitLocal(),
                  enabled: !_loading,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13)),
                ],
                const SizedBox(height: 16),

                FilledButton(
                  onPressed: _loading ? null : _submitLocal,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2,
                              color: Colors.white))
                      : Text(_isCreatingAccount ? 'Create Account' : 'Sign In'),
                ),
                const SizedBox(height: 8),

                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _isCreatingAccount = !_isCreatingAccount;
                            _error = null;
                          }),
                  child: Text(
                    _isCreatingAccount && _hasLocalAccount
                        ? 'Already have an account? Sign in'
                        : _isCreatingAccount
                            ? 'Already have an account? Sign in'
                            : 'No account yet? Create one',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
