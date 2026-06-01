import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/services/ai_service.dart';

void main() {
  group('buildCustomRewritePrompt', () {
    const note = 'My note content.';

    test('buildCustomRewritePrompt_genericInstruction_includesNoDashRule', () {
      final prompt = buildCustomRewritePrompt(note, 'Make it more formal');
      expect(prompt, contains('Do not use dashes or hyphens as list markers'));
    });

    test('buildCustomRewritePrompt_genericInstruction_includesNote', () {
      final prompt = buildCustomRewritePrompt(note, 'Make it shorter');
      expect(prompt, contains(note));
    });

    test('buildCustomRewritePrompt_genericInstruction_includesReturnOnly', () {
      final prompt = buildCustomRewritePrompt(note, 'Summarize it');
      expect(prompt, contains('Return only the rewritten text'));
    });

    test('buildCustomRewritePrompt_instructionMentionsDash_omitsNoDashRule', () {
      final prompt = buildCustomRewritePrompt(note, 'Use dashes for bullet points');
      expect(prompt, isNot(contains('Do not use dashes')));
    });

    test('buildCustomRewritePrompt_instructionMentionsHyphen_omitsNoDashRule', () {
      final prompt = buildCustomRewritePrompt(note, 'Use hyphens as separators');
      expect(prompt, isNot(contains('Do not use dashes')));
    });

    test('buildCustomRewritePrompt_caseInsensitiveDashDetection', () {
      final prompt = buildCustomRewritePrompt(note, 'Add DASHES between items');
      expect(prompt, isNot(contains('Do not use dashes')));
    });

    test('buildCustomRewritePrompt_includesCustomInstruction', () {
      final prompt = buildCustomRewritePrompt(note, 'Make it a poem');
      expect(prompt, contains('Make it a poem'));
    });
  });
}
