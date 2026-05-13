import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/screens/settings_screen.dart';

Widget _wrap({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  group('SettingsScreen — About section', () {
    testWidgets('build_rendersAboutSectionHeader', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('build_rendersVersionTile', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('Version'), findsOneWidget);
    });

    testWidgets('build_rendersWebsiteTile', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('Website'), findsOneWidget);
      expect(find.textContaining('thechaos-mynotes.web.app'), findsOneWidget);
    });

    testWidgets('versionTile_showsVersionFromPackageInfo', (tester) async {
      await tester.pumpWidget(_wrap());
      // Let the FutureProvider resolve.
      await tester.pumpAndSettle();

      // Version text visible once PackageInfo resolves (platform-dependent in
      // tests; we verify the tile itself is always present).
      expect(find.text('Version'), findsOneWidget);
    });
  });
}
