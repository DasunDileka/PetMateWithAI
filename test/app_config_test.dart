import 'package:flutter_test/flutter_test.dart';
import 'package:petmate/core/config/app_config.dart';

/// Guards on build-time configuration.
///
/// These are cheap but catch changes that would be expensive to notice later —
/// a paid model slipping into the fallback slot, or a removed timeout letting
/// an AI request hang the UI indefinitely.
void main() {
  group('AI provider configuration', () {
    test('OpenRouter fallback is pinned to a free model', () {
      // The brief requires the fallback to be free. A paid slug here would
      // silently start costing money on every Gemini failure.
      expect(AppConfig.openRouterModel.endsWith(':free'), isTrue,
          reason: 'OpenRouter fallback must be a :free model, '
              'got ${AppConfig.openRouterModel}');
    });

    test('prompt context is capped', () {
      // Bounds both cost and how much pet data leaves the device.
      expect(AppConfig.maxContextChars, greaterThan(0));
      expect(AppConfig.maxContextChars, lessThanOrEqualTo(8000));
    });

    test('AI requests cannot hang indefinitely', () {
      expect(AppConfig.aiTimeout.inSeconds, greaterThan(0));
      expect(AppConfig.aiTimeout.inSeconds, lessThanOrEqualTo(60));
    });

    test('insight caching is enabled, so reopening a screen costs nothing', () {
      expect(AppConfig.insightCacheTtl, greaterThan(Duration.zero));
    });

    test('history queries are paginated', () {
      expect(AppConfig.historyPageSize, greaterThan(0));
      expect(AppConfig.historyPageSize, lessThanOrEqualTo(100));
    });
  });
}
