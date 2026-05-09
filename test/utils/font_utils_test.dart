import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/utils/font_utils.dart';

void main() {
  group('macFontStyleBuilder', () {
    test('sans-serif_mapsToHelveticaNeue', () {
      final attr = Attribute('font', AttributeScope.inline, 'sans-serif');
      final style = macFontStyleBuilder(attr);
      expect(style.fontFamily, 'Helvetica Neue');
    });

    test('serif_mapsToTimesNewRoman', () {
      final attr = Attribute('font', AttributeScope.inline, 'serif');
      final style = macFontStyleBuilder(attr);
      expect(style.fontFamily, 'Times New Roman');
    });

    test('monospace_mapsToMenlo', () {
      final attr = Attribute('font', AttributeScope.inline, 'monospace');
      final style = macFontStyleBuilder(attr);
      expect(style.fontFamily, 'Menlo');
    });

    test('bundledFont_returnsEmptyStyle', () {
      final attr = Attribute('font', AttributeScope.inline, 'nunito');
      final style = macFontStyleBuilder(attr);
      expect(style, const TextStyle());
    });

    test('nonFontAttribute_returnsEmptyStyle', () {
      final style = macFontStyleBuilder(Attribute.bold);
      expect(style, const TextStyle());
    });

    test('nullFontValue_returnsEmptyStyle', () {
      final attr = Attribute('font', AttributeScope.inline, null);
      final style = macFontStyleBuilder(attr);
      expect(style, const TextStyle());
    });
  });

  group('kMacGenericFontMap', () {
    test('containsExactlyThreeGenericFamilies', () {
      expect(kMacGenericFontMap.keys,
          containsAll(['sans-serif', 'serif', 'monospace']));
      expect(kMacGenericFontMap.length, 3);
    });
  });

  group('kBundledFontAssets', () {
    test('containsAllDecorativeFamilies', () {
      expect(kBundledFontAssets.keys, containsAll([
        'nunito', 'pacifico', 'roboto-mono', 'ibarra-real-nova', 'square-peg',
      ]));
    });

    test('eachFamilyHasAtLeastOneAsset', () {
      for (final entry in kBundledFontAssets.entries) {
        expect(entry.value, isNotEmpty,
            reason: '${entry.key} has no font assets');
      }
    });
  });
}
