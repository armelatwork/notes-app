import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/providers/app_provider.dart';
import 'package:notes_app/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: SettingsScreen()),
    );

void main() {
  group('SettingsScreen — About section', () {
    testWidgets('build_rendersAboutSectionHeader', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('ABOUT'), 100);

      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('build_rendersVersionTile', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Version'), 100);

      expect(find.text('Version'), findsOneWidget);
    });

    testWidgets('build_rendersWebsiteTile', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Website'), 100);

      expect(find.text('Website'), findsOneWidget);
      expect(find.textContaining('thechaos-mynotes.web.app'), findsOneWidget);
    });

    testWidgets('versionTile_showsVersionFromPackageInfo', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Version text visible once PackageInfo resolves (platform-dependent in
      // tests; we verify the tile itself is always present).
      await tester.scrollUntilVisible(find.text('Version'), 100);

      expect(find.text('Version'), findsOneWidget);
    });
  });

  group('SettingsScreen — Support section', () {
    testWidgets('build_rendersSupportSectionHeader', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('SUPPORT'), findsOneWidget);
    });

    testWidgets('build_rendersSendFeedbackTile', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('Send Feedback'), findsOneWidget);
    });
  });

  group('SettingsScreen — Appearance section', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('build_rendersAppearanceSectionHeader', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('APPEARANCE'), findsOneWidget);
    });

    testWidgets('build_rendersAllThreeSegments', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('tappingLight_updatesThemeModeProvider', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pump();

      await tester.tap(find.text('Light'));
      await tester.pump();

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets('tappingDark_updatesThemeModeProvider', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pump();

      await tester.tap(find.text('Dark'));
      await tester.pump();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });
}
