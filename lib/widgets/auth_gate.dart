import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../screens/auth_screen.dart';
import '../screens/home_screen.dart';

const _macAppMenuChannel = MethodChannel('com.armelchao.notesApp/appMenu');

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await ref.read(appUserProvider.notifier).tryRestore();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // On macOS, Flutter resets NSApp.mainMenu on every widget-tree rebuild.
    // When the user logs out, notify the native side to restore the app menu
    // after Flutter finishes the rebuild.
    if (Platform.isMacOS) {
      ref.listen(appUserProvider, (prev, next) {
        if (prev != null && next == null) {
          Future.delayed(const Duration(milliseconds: 300),
              () => _macAppMenuChannel.invokeMethod<void>('restore'));
        }
      });
    }

    final user = ref.watch(appUserProvider);
    return user == null ? const AuthScreen() : const HomeScreen();
  }
}
