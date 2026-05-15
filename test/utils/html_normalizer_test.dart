import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/utils/html_normalizer.dart';

void main() {
  group('normalizeHtml', () {
    // ── MS Word ───────────────────────────────────────────────────────────────

    test('stripMsWordArtefacts_removesOfficeNamespaceElements', () {
      const input = '<p>Hello<o:p>&nbsp;</o:p> world</p>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('<o:')));
      expect(result, contains('Hello'));
      expect(result, contains('world'));
    });

    test('stripMsWordArtefacts_removesMsoNormalClass', () {
      // MS Word outputs class=MsoNormal unquoted.
      const input = '<p class=MsoNormal>Text</p>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('MsoNormal')));
    });

    // ── Google Docs ───────────────────────────────────────────────────────────

    test('unwrapGoogleDocsMarker_removesDocsInternalGuidWrapper', () {
      const input =
          '<b id="docs-internal-guid-abc" style="font-weight:normal;">'
          '<p>Hello</p></b>';
      final result = normalizeHtml(input);
      expect(result, contains('<p>Hello</p>'));
      expect(result, isNot(contains('docs-internal-guid')));
    });

    test('marginLeft_convertsToLeadingTab', () {
      const input = '<p style="margin-left: 36pt;">Indented</p>';
      final result = normalizeHtml(input);
      // One level → one leading \t injected after the opening <p> tag.
      expect(result, contains('\tIndented'));
    });

    test('marginLeft_twoLevelsProducesTwoTabs', () {
      const input = '<p style="margin-left: 72pt;">Deep</p>';
      final result = normalizeHtml(input);
      expect(result, contains('\t\tDeep'));
    });

    test('marginLeft_zeroProducesNoTab', () {
      const input = '<p style="margin-left: 0pt;">Normal</p>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('\t')));
    });

    // ── Apple Notes ───────────────────────────────────────────────────────────

    test('cleanApple_removesInterchangeNewlineMarker', () {
      const input =
          '<p>Hello<br class="Apple-interchange-newline"/>World</p>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('Apple-interchange-newline')));
    });

    test('cleanApple_replacesTabSpanWithFourSpaces', () {
      const input =
          '<p>A<span class="Apple-tab-span">\t</span>B</p>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('Apple-tab-span')));
      expect(result, contains('    '));
    });

    // ── List blank lines ──────────────────────────────────────────────────────

    test('listBlankLines_preservesBlankLineAfterListItem', () {
      const input =
          '<ul><li><p>Item<span><br/></span></p></li></ul>';
      final result = normalizeHtml(input);
      expect(result, contains('<p></p>'));
    });

    test('listBlankLines_splitsListAtBlankParagraph', () {
      const input = '<ul><li>A</li><p></p><li>B</li></ul>';
      final result = normalizeHtml(input);
      // The list is split — <p></p> appears outside the list context.
      expect(result, contains('<p></p>'));
      // Both lists should be present after the split.
      expect(result, contains('<ul>'));
    });

    // ── Block splitting ───────────────────────────────────────────────────────

    test('splitTagAtBr_splitsParagraphAtBr', () {
      const input = '<p>Line1<br/>Line2</p>';
      final result = normalizeHtml(input);
      // Should produce two <p> elements instead of one.
      expect(RegExp(r'<p>').allMatches(result).length, greaterThanOrEqualTo(2));
    });

    test('splitTagAtBr_preservesEmptyParagraphForBrOnlyContent', () {
      const input = '<p></p><p><br/></p><p>Text</p>';
      final result = normalizeHtml(input);
      expect(result, contains('Text'));
    });

    test('cleanBlocks_removesImgTags', () {
      const input = '<p>Text<img src="photo.png"/>After</p>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('<img')));
      expect(result, contains('Text'));
    });

    test('cleanBlocks_unwrapsPNestedInLi', () {
      const input = '<ul><li><p>Item text</p></li></ul>';
      final result = normalizeHtml(input);
      // <li><p>…</p></li> → <li>…</li>
      expect(result, isNot(contains('<li><p>')));
      expect(result, contains('Item text'));
    });

    // ── Inline styles → semantic ──────────────────────────────────────────────

    test('inlineToSemantic_convertsBoldSpanToStrong', () {
      const input = '<span style="font-weight: bold;">Bold</span>';
      final result = normalizeHtml(input);
      expect(result, contains('<strong>Bold</strong>'));
    });

    test('inlineToSemantic_convertsItalicSpanToEm', () {
      const input = '<span style="font-style: italic;">Italic</span>';
      final result = normalizeHtml(input);
      expect(result, contains('<em>Italic</em>'));
    });

    test('inlineToSemantic_preservesColorAsSpan', () {
      const input = '<span style="color: red;">Red</span>';
      final result = normalizeHtml(input);
      expect(result, contains('color: red'));
    });

    test('inlineToSemantic_dropsTransparentColor', () {
      const input = '<span style="color: transparent;">Hidden</span>';
      final result = normalizeHtml(input);
      expect(result, isNot(contains('color: transparent')));
    });

    // ── Paragraph gaps ────────────────────────────────────────────────────────

    test('insertParagraphGaps_insertsEmptyParaBetweenBrAndBlock', () {
      const input = '<p>A</p><br/><p>B</p>';
      final result = normalizeHtml(input);
      expect(result, contains('<p></p>'));
    });

    test('insertParagraphGaps_insertsBrBetweenAdjacentParas', () {
      const input = '<p>A</p><p>B</p>';
      final result = normalizeHtml(input);
      expect(result, contains('</p><br/><p'));
    });
  });
}
