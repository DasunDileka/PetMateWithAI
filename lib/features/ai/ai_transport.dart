import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../shared/models/ai_models.dart';

/// One conversational turn sent to a model.
class AiTurn {
  const AiTurn.user(this.text) : role = ChatRole.user;
  const AiTurn.assistant(this.text) : role = ChatRole.assistant;

  final ChatRole role;
  final String text;
}

/// A single way of reaching a language model.
///
/// Keeping this an interface is what makes the provider strategy swappable:
/// the Cloudflare gateway, Gemini and OpenRouter are interchangeable from the
/// service layer's point of view, and adding a fourth provider later requires
/// no change above this line.
abstract class AiTransport {
  const AiTransport();

  AiProvider get provider;

  /// True when this transport has the configuration it needs to run.
  bool get isConfigured;

  Future<AiResult> complete({
    required String system,
    required List<AiTurn> messages,
    int maxTokens = 700,
  });
}

/// Preferred production transport: a Cloudflare Worker holds the provider keys
/// and verifies the caller's Firebase ID token. The device never sees a
/// provider key.
class GatewayTransport extends AiTransport {
  const GatewayTransport({this.client});

  final http.Client? client;

  @override
  AiProvider get provider => AiProvider.gateway;

  @override
  bool get isConfigured => AppConfig.useGateway;

  @override
  Future<AiResult> complete({
    required String system,
    required List<AiTurn> messages,
    int maxTokens = 700,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AiException('Please sign in again to use the assistant.',
          code: 'unauthenticated');
    }

    final String token = await user.getIdToken() ?? '';
    final http.Client c = client ?? http.Client();

    try {
      final http.Response res = await c
          .post(
            Uri.parse(AppConfig.aiGatewayUrl),
            headers: <String, String>{
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{
              'system': system,
              'maxTokens': maxTokens,
              'messages': messages
                  .map((m) => <String, String>{
                        'role': m.role.name,
                        'text': m.text,
                      })
                  .toList(),
            }),
          )
          .timeout(AppConfig.aiTimeout);

      // Decoded defensively: a gateway that is down answers with an HTML
      // error page, and parsing that as JSON threw a FormatException out of
      // this method before the status code was ever looked at.
      Map<String, dynamic> body = <String, dynamic>{};
      try {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        // Leave `body` empty; the status checks below produce the message.
      }

      if (res.statusCode == 429) {
        throw const AiException(
          'You have made a lot of AI requests just now. Please wait a moment '
          'and try again.',
          code: 'rate_limited',
        );
      }

      if (res.statusCode != 200 || body['ok'] != true) {
        throw AiException(
          (body['message'] as String?) ??
              'The assistant is unavailable right now.',
          code: body['code'] as String?,
        );
      }

      return AiResult(
        text: (body['text'] as String? ?? '').trim(),
        provider: AiProvider.gateway,
        model: body['model'] as String?,
        latencyMs: body['latencyMs'] as int?,
      );
    } on TimeoutException {
      throw const AiException(
        'The assistant took too long to respond. Please try again.',
        code: 'timeout',
      );
    } finally {
      if (client == null) c.close();
    }
  }
}

/// Direct Gemini transport. Used in development and when no gateway is
/// deployed. The key arrives via `--dart-define`, never from source.
class GeminiTransport extends AiTransport {
  const GeminiTransport({this.client});

  final http.Client? client;

  /// Extra token budget reserved for the model's internal reasoning, on top of
  /// the visible answer length the caller asked for. Measured against
  /// gemini-3.6-flash, which spends roughly 300–450 tokens thinking on these
  /// prompts.
  static const int _reasoningAllowanceTokens = 1024;

  @override
  AiProvider get provider => AiProvider.gemini;

  @override
  bool get isConfigured => AppConfig.hasDirectGemini;

  @override
  Future<AiResult> complete({
    required String system,
    required List<AiTurn> messages,
    int maxTokens = 700,
  }) async {
    final Uri uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${AppConfig.geminiModel}:generateContent',
    );

    final http.Client c = client ?? http.Client();
    final Stopwatch sw = Stopwatch()..start();

    try {
      final http.Response res = await c
          .post(
            uri,
            headers: <String, String>{
              'content-type': 'application/json',
              // Header auth rather than a query string keeps the key out of
              // request logs and out of any URL that might be captured.
              'x-goog-api-key': AppConfig.geminiApiKey,
            },
            body: jsonEncode(<String, dynamic>{
              'systemInstruction': <String, dynamic>{
                'parts': <Map<String, String>>[
                  <String, String>{'text': system}
                ],
              },
              'contents': messages
                  .map((m) => <String, dynamic>{
                        'role': m.role == ChatRole.assistant ? 'model' : 'user',
                        'parts': <Map<String, String>>[
                          <String, String>{'text': m.text}
                        ],
                      })
                  .toList(),
              'generationConfig': <String, dynamic>{
                'temperature': 0.6,
                'topP': 0.9,
                // Gemini 3 reasons before answering, and those reasoning
                // tokens are charged against maxOutputTokens. Requesting
                // exactly the visible length we want starves the answer and
                // truncates it mid-sentence (finishReason MAX_TOKENS with a
                // large thoughtsTokenCount), so the budget is the requested
                // length plus a reasoning allowance. Reasoning is also kept
                // short: these tasks restate statistics the app already
                // computed, so deep deliberation buys nothing.
                'maxOutputTokens': maxTokens + _reasoningAllowanceTokens,
                'thinkingConfig': <String, String>{'thinkingLevel': 'low'},
              },
            }),
          )
          .timeout(AppConfig.aiTimeout);

      sw.stop();

      if (res.statusCode != 200) {
        // The provider's own error text can contain the request echo; never
        // surface it to the user.
        if (kDebugMode) {
          debugPrint('Gemini HTTP ${res.statusCode}');
        }
        throw AiException(
          _messageForStatus(res.statusCode),
          code: 'gemini_http_${res.statusCode}',
        );
      }

      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;

      final List<dynamic> candidates =
          (body['candidates'] as List<dynamic>?) ?? const <dynamic>[];

      if (candidates.isEmpty) {
        // Usually a safety block on the provider side.
        throw const AiException(
          'The assistant could not produce an answer for that. Try rephrasing '
          'your question.',
          code: 'empty_candidates',
        );
      }

      final Map<String, dynamic> content =
          (candidates.first as Map<String, dynamic>)['content']
                  as Map<String, dynamic>? ??
              <String, dynamic>{};

      final List<dynamic> parts =
          (content['parts'] as List<dynamic>?) ?? const <dynamic>[];

      final String text = parts
          .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
          .join()
          .trim();

      if (text.isEmpty) {
        throw const AiException(
          'The assistant returned an empty response. Please try again.',
          code: 'empty_response',
        );
      }

      return AiResult(
        text: text,
        provider: AiProvider.gemini,
        model: AppConfig.geminiModel,
        latencyMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      throw const AiException(
        'The assistant took too long to respond. Please try again.',
        code: 'timeout',
      );
    } on FormatException {
      throw const AiException(
        'The assistant sent back an unreadable response.',
        code: 'bad_format',
      );
    } finally {
      if (client == null) c.close();
    }
  }

  static String _messageForStatus(int status) => switch (status) {
        400 => 'The assistant rejected that request. Please try rephrasing.',
        401 || 403 =>
          'The assistant is not configured correctly. Please check the API key.',
        429 =>
          'The AI service is busy right now. Please wait a moment and try again.',
        >= 500 => 'The AI service is temporarily unavailable.',
        _ => 'The assistant could not be reached.',
      };
}

/// Fallback transport. Restricted to free OpenRouter models so the fallback
/// path can never incur cost.
class OpenRouterTransport extends AiTransport {
  const OpenRouterTransport({this.client});

  final http.Client? client;

  @override
  AiProvider get provider => AiProvider.openRouter;

  @override
  bool get isConfigured =>
      AppConfig.hasDirectOpenRouter && AppConfig.openRouterModel.endsWith(':free');

  @override
  Future<AiResult> complete({
    required String system,
    required List<AiTurn> messages,
    int maxTokens = 700,
  }) async {
    final http.Client c = client ?? http.Client();
    final Stopwatch sw = Stopwatch()..start();

    try {
      final http.Response res = await c
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: <String, String>{
              'content-type': 'application/json',
              'authorization': 'Bearer ${AppConfig.openRouterApiKey}',
              'x-title': AppConfig.appName,
            },
            body: jsonEncode(<String, dynamic>{
              'model': AppConfig.openRouterModel,
              'max_tokens': maxTokens,
              'temperature': 0.6,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'system', 'content': system},
                ...messages.map((m) => <String, String>{
                      'role': m.role == ChatRole.assistant ? 'assistant' : 'user',
                      'content': m.text,
                    }),
              ],
            }),
          )
          .timeout(AppConfig.aiTimeout);

      sw.stop();

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('OpenRouter HTTP ${res.statusCode}');
        }
        throw AiException(
          GeminiTransport._messageForStatus(res.statusCode),
          code: 'openrouter_http_${res.statusCode}',
        );
      }

      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;

      final List<dynamic> choices =
          (body['choices'] as List<dynamic>?) ?? const <dynamic>[];

      if (choices.isEmpty) {
        throw const AiException(
          'The assistant returned an empty response. Please try again.',
          code: 'empty_response',
        );
      }

      final Map<String, dynamic> message =
          (choices.first as Map<String, dynamic>)['message']
                  as Map<String, dynamic>? ??
              <String, dynamic>{};

      final String text = (message['content'] as String? ?? '').trim();

      if (text.isEmpty) {
        throw const AiException(
          'The assistant returned an empty response. Please try again.',
          code: 'empty_response',
        );
      }

      return AiResult(
        text: text,
        provider: AiProvider.openRouter,
        model: AppConfig.openRouterModel,
        latencyMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      throw const AiException(
        'The assistant took too long to respond. Please try again.',
        code: 'timeout',
      );
    } on FormatException {
      throw const AiException(
        'The assistant sent back an unreadable response.',
        code: 'bad_format',
      );
    } finally {
      if (client == null) c.close();
    }
  }
}

/// Tries each configured transport in order and returns the first success.
///
/// Order is gateway → Gemini → OpenRouter, so the most secure option wins when
/// it is available and the app still functions when it is not.
class AiClient {
  AiClient({List<AiTransport>? transports})
      : _transports = transports ??
            const <AiTransport>[
              GatewayTransport(),
              GeminiTransport(),
              OpenRouterTransport(),
            ];

  final List<AiTransport> _transports;

  List<AiTransport> get available =>
      _transports.where((t) => t.isConfigured).toList(growable: false);

  bool get hasTransport => available.isNotEmpty;

  Future<AiResult> complete({
    required String system,
    required List<AiTurn> messages,
    int maxTokens = 700,
  }) async {
    final List<AiTransport> usable = available;

    if (usable.isEmpty) {
      throw const AiException(
        'AI features are not configured in this build.',
        code: 'not_configured',
      );
    }

    AiException? lastError;

    for (final AiTransport transport in usable) {
      try {
        return await transport.complete(
          system: system,
          messages: messages,
          maxTokens: maxTokens,
        );
      } on AiException catch (e) {
        lastError = e;

        // A rejected request or a missing sign-in will fail identically on the
        // next provider, so there is nothing to gain by retrying it.
        if (e.code == 'unauthenticated' || e.code == 'not_configured') rethrow;

        if (kDebugMode) {
          debugPrint('AI transport ${transport.provider.name} failed: ${e.code}');
        }
      } catch (e) {
        lastError = const AiException(
          'The assistant could not be reached. Check your connection.',
          code: 'network',
        );
        if (kDebugMode) debugPrint('AI transport error: $e');
      }
    }

    throw lastError ??
        const AiException('The assistant is unavailable.', code: 'unknown');
  }
}
