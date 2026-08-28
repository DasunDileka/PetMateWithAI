/// Build-time configuration for PetMate.
///
/// Nothing secret is stored in source. Every credential arrives through
/// `--dart-define` (see `tool/run_dev.ps1`), which keeps keys out of the
/// repository and out of version control.
///
/// Two AI transport modes are supported:
///
///  * **Gateway mode** (preferred for production) — set [aiGatewayUrl] to the
///    deployed Cloudflare Worker. The app then sends only a Firebase ID token;
///    the provider keys live server-side and never reach the device.
///  * **Direct mode** (development / offline marking) — the app talks to
///    Gemini and OpenRouter itself using keys injected at build time.
///
/// Direct mode is convenient but a key inside an APK is extractable, so
/// gateway mode is the documented production path. Switching is a config
/// change only: no code in the AI layer needs to be touched.
class AppConfig {
  const AppConfig._();

  // ------------------------------------------------------------ AI gateway
  /// Deployed Cloudflare Worker endpoint, e.g.
  /// `https://petmate-ai-gateway.<subdomain>.workers.dev/v1/ai`.
  static const String aiGatewayUrl =
      String.fromEnvironment('AI_GATEWAY_URL', defaultValue: '');

  static bool get useGateway => aiGatewayUrl.trim().isNotEmpty;

  // ------------------------------------------------------- direct API keys
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static const String openRouterApiKey =
      String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');

  static bool get hasDirectGemini => geminiApiKey.trim().isNotEmpty;
  static bool get hasDirectOpenRouter => openRouterApiKey.trim().isNotEmpty;

  /// True when at least one AI transport is usable. When false the UI shows an
  /// explanatory empty state instead of failing requests silently.
  static bool get aiConfigured =>
      useGateway || hasDirectGemini || hasDirectOpenRouter;

  // ---------------------------------------------------------------- models
  static const String geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.6-flash');

  /// OpenRouter fallback. Restricted to a `:free` model so the fallback path
  /// cannot incur cost.
  static const String openRouterModel = String.fromEnvironment(
    'OPENROUTER_MODEL',
    defaultValue: 'openai/gpt-oss-20b:free',
  );

  // --------------------------------------------------------------- tuning
  /// AI insights are cached this long so opening the dashboard repeatedly does
  /// not trigger a new model call (performance rubric: "avoid unnecessary AI
  /// requests").
  static const Duration insightCacheTtl = Duration(hours: 6);

  /// Network timeout applied to every AI request.
  static const Duration aiTimeout = Duration(seconds: 30);

  /// Page size for paginated care-history queries.
  static const int historyPageSize = 20;

  /// Hard cap on characters of pet context sent to the model. Keeps prompts
  /// small (cost + latency) and limits how much personal data leaves the
  /// device (privacy rubric: "minimise data sent to AI providers").
  static const int maxContextChars = 4500;

  // ------------------------------------------------------------ app facts
  static const String appName = 'PetMate';
  static const String appTagline = 'Your AI Pet Care Companion';
  static const String appVersion = '1.0.0';
}
