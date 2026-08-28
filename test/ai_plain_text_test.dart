import 'package:flutter_test/flutter_test.dart';
import 'package:petmate/features/ai/ai_service.dart';

/// Tests for the markdown stripper applied to every model response.
///
/// This exists because providers vary in how well they follow a "plain text
/// only" instruction, and the OpenRouter fallback is a different model family
/// from Gemini. Unstripped markdown reached the UI during testing as a literal
/// `**Key Figures:**`, so the rules are pinned here.
void main() {
  group('removes emphasis', () {
    test('strips bold', () {
      expect(AiService.plainText('**Key Figures:** 11 of 13'),
          'Key Figures: 11 of 13');
    });

    test('strips underscore bold', () {
      expect(AiService.plainText('__Important__ note'), 'Important note');
    });

    test('strips italics', () {
      expect(AiService.plainText('Bruno was *very* active'),
          'Bruno was very active');
    });

    test('strips inline code', () {
      expect(AiService.plainText('Use `gemini-3.6-flash` today'),
          'Use gemini-3.6-flash today');
    });

    test('strips heading markers', () {
      expect(AiService.plainText('## Summary\nAll good'), 'Summary\nAll good');
    });

    test('handles bold spanning a line break', () {
      expect(AiService.plainText('**two\nlines**'), 'two\nlines');
    });
  });

  group('normalises lists', () {
    test('converts asterisk bullets to dashes', () {
      expect(
        AiService.plainText('* first\n* second'),
        '- first\n- second',
      );
    });

    test('converts bullet characters to dashes', () {
      expect(AiService.plainText('• one\n• two'), '- one\n- two');
    });
  });

  group('leaves ordinary text intact', () {
    test('plain sentences are unchanged', () {
      const String s =
          'Bruno completed 11 of 13 feedings (85%). Activity is 44% lower.';
      expect(AiService.plainText(s), s);
    });

    test('a lone asterisk is not treated as emphasis', () {
      expect(AiService.plainText('2 * 3 = 6'), '2 * 3 = 6');
    });

    test('snake_case identifiers survive', () {
      expect(AiService.plainText('field day_key holds the date'),
          'field day_key holds the date');
    });

    test('trims surrounding whitespace', () {
      expect(AiService.plainText('  hello  '), 'hello');
    });

    test('empty input stays empty', () {
      expect(AiService.plainText(''), '');
    });
  });
}
