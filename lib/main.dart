import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/auth_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NotesApp()));
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        FlutterQuillLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD60A),
          brightness: Brightness.light,
        ),
        fontFamily: 'SF Pro Text',
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD60A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: Platform.isMacOS
          ? PlatformMenuBar(
              menus: [
                PlatformMenu(
                  label: 'My Notes',
                  menus: [
                    PlatformMenuItemGroup(members: [
                      PlatformProvidedMenuItem(
                          type: PlatformProvidedMenuItemType.about),
                    ]),
                    PlatformMenuItemGroup(members: [
                      PlatformProvidedMenuItem(
                          type: PlatformProvidedMenuItemType.hide),
                      PlatformProvidedMenuItem(
                          type: PlatformProvidedMenuItemType.hideOtherApplications),
                      PlatformProvidedMenuItem(
                          type: PlatformProvidedMenuItemType.showAllApplications),
                    ]),
                    PlatformMenuItemGroup(members: [
                      PlatformProvidedMenuItem(
                          type: PlatformProvidedMenuItemType.quit),
                    ]),
                  ],
                ),
              ],
              child: const AuthGate(),
            )
          : const AuthGate(),
    );
  }
}
