import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/services/firestore_refs.dart';
import '../../shared/models/ai_models.dart';
import '../analytics/care_analytics.dart';
import 'ai_prompts.dart';
import 'ai_safety.dart';
import 'ai_transport.dart';
import 'pet_context_builder.dart';

/// Orchestrates every AI feature in PetMate.
///
/// Responsibilities, in the order they matter:
///  1. **Safety** — clinical requests are intercepted before any network call.
///  2. **Caching** — a generated insight is reused while the underlying data
///     is unchanged and recent, so opening the dashboard does not spend a model
///     call every time (an explicit performance requirement).
///  3. **Grounding** — the prompt carries statistics computed by
///     [CareAnalytics]; the model phrases them rather than deriving them.
///  4. **Fallback** — [AiClient] walks gateway → Gemini → OpenRouter.
///
/// The UI layer talks only to this class and never to a transport directly.
class AiService {
  AiService({
    required this.uid,
    AiClient? client,
  }) : _client = client ?? AiClient();

  final String uid;
  final AiClient _client;

  bool get isConfigured => _client.hasTransport;

  /// Providers usable in this build, for the diagnostics panel on the profile
  /// screen (useful when demonstrating the fallback chain).
  List<AiProvider> get availableProviders =>
      _client.available.map((t) => t.provider).toList(growable: false);

  // ================================================================ insights

  /// Returns a cached insight when the pet's data has not changed, otherwise
  /// generates and stores a fresh one.
  ///
  /// [force] bypasses the cache for the pull-to-refresh action.
  Future<AiInsight> insight({
    required String petId,
    required AiInsightKind kind,
    required PetContext context,
    required String petName,
    bool force = false,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref =
        Refs.aiInsights(uid, petId).doc(kind.name);

    if (!force) {
      final AiInsight? cached = await _readCachedInsight(ref);
      if (cached != null &&
          cached.matches(context.fingerprint, AppConfig.insightCacheTtl)) {
        return cached;
      }
    }

    final String system = switch (kind) {
      AiInsightKind.dailyBrief => AiPrompts.dailyInsight(),
      AiInsightKind.trend => AiPrompts.trendAnalysis(),
      AiInsightKind.anomaly => AiPrompts.anomalyExplanation(),
      AiInsightKind.vetSummary => AiPrompts.vetSummary(),
    };

    final String instruction = switch (kind) {
      AiInsightKind.dailyBrief =>
        'Write today\'s care insight for $petName.',
      AiInsightKind.trend =>
        'Explain $petName\'s recorded activity trend.',
      AiInsightKind.anomaly =>
        'Explain the detected pattern to the owner.',
      AiInsightKind.vetSummary =>
        'Summarise $petName\'s recent records for a veterinary appointment.',
    };

    try {
      final AiResult result = await _client.complete(
        system: system,
        messages: <AiTurn>[
          AiTurn.user('${context.text}\n\n$instruction'),
        ],
        maxTokens: kind == AiInsightKind.vetSummary ? 900 : 400,
      );

      final AiInsight insight = AiInsight(
        id: kind.name,
        kind: kind,
        text: plainText(result.text),
        generatedAt: DateTime.now(),
        provider: result.provider,
        model: result.model,
        contextFingerprint: context.fingerprint,
        latencyMs: result.latencyMs,
      );

      // Cache write must never break the feature that produced it.
      unawaited(_writeInsight(ref, insight));

      return insight;
    } on AiException {
      // If the network call failed, a stale cached insight is still more useful
      // to the owner than an error — clearly labelled as previously generated.
      final AiInsight? stale = await _readCachedInsight(ref);
      if (stale != null) return stale;
      rethrow;
    }
  }

  Future<AiInsight?> _readCachedInsight(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await ref.get();
      final Map<String, dynamic>? data = snap.data();
      return data == null ? null : AiInsight.fromMap(snap.id, data);
    } catch (e) {
      if (kDebugMode) debugPrint('insight cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeInsight(
    DocumentReference<Map<String, dynamic>> ref,
    AiInsight insight,
  ) async {
    try {
      await ref.set(insight.toMap());
    } catch (e) {
      if (kDebugMode) debugPrint('insight cache write failed: $e');
    }
  }

  // ==================================================================== chat

  /// Answers a chat message about [petName].
  ///
  /// Returns a locally generated response without contacting any provider when
  /// the safety layer blocks the request.
  Future<AiResult> chat({
    required String question,
    required String petName,
    required PetContext context,
    List<ChatMessage> history = const <ChatMessage>[],
  }) async {
    final SafetyAssessment assessment = AiSafety.assess(question);

    if (assessment.isBlocked) {
      if (kDebugMode) {
        debugPrint('AI safety: blocked on "${assessment.matched}"');
      }
      return AiResult(
        text: AiSafety.isEmergency(question)
            ? AiSafety.emergencyResponse(petName)
            : AiSafety.clinicalRefusal(petName),
        provider: AiProvider.local,
        model: 'safety-guardrail',
        latencyMs: 0,
      );
    }

    final String system = assessment.verdict == SafetyVerdict.cautious
        ? AiPrompts.withCaution(AiPrompts.chat(), AiSafety.cautiousInstruction)
        : AiPrompts.chat();

    // Only the last few turns are replayed: enough for the conversation to feel
    // continuous, bounded so the prompt cannot grow without limit. Error turns
    // are excluded so a failure is never treated as something the assistant
    // actually said.
    final List<AiTurn> turns = <AiTurn>[
      AiTurn.user(context.text),
      ...history
          .where((m) => !m.isError)
          .toList()
          .reversed
          .take(6)
          .toList()
          .reversed
          .map((m) => m.isUser
              ? AiTurn.user(m.text)
              : AiTurn.assistant(m.text)),
      AiTurn.user(question),
    ];

    final AiResult result =
        await _client.complete(system: system, messages: turns, maxTokens: 600);

    return AiResult(
      text: plainText(result.text),
      provider: result.provider,
      model: result.model,
      latencyMs: result.latencyMs,
      fromCache: result.fromCache,
    );
  }

  /// Strips markdown emphasis from model output.
  ///
  /// Public so the stripping rules can be unit-tested directly.
  ///
  /// The prompts ask for plain text, but instruction-following varies between
  /// providers and the OpenRouter fallback is a different model family
  /// entirely. Without this, a stray `**Key Figures:**` renders in the UI as
  /// literal asterisks. Cheaper and more reliable than rendering markdown for
  /// what should be a few short sentences.
  static String plainText(String input) {
    // Note: `replaceAll` takes a *literal* replacement in Dart — `$1` would be
    // inserted verbatim. Anything unwrapping a capture group must therefore go
    // through `replaceAllMapped`.
    String out = input
        // ### Heading -> Heading
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        // Normalise bullet markers to a consistent dash.
        .replaceAll(RegExp(r'^\s*[*•]\s+', multiLine: true), '- ');

    String unwrap(String s, RegExp pattern) =>
        s.replaceAllMapped(pattern, (Match m) => m[1] ?? '');

    // **bold** / __bold__
    out = unwrap(out, RegExp(r'\*\*(.+?)\*\*', dotAll: true));
    out = unwrap(out, RegExp(r'__(.+?)__', dotAll: true));
    // *italic* / _italic_ — only when wrapping non-space content, so that
    // ordinary asterisks and snake_case identifiers survive.
    out = unwrap(out, RegExp(r'(?<!\w)\*(\S(?:.*?\S)?)\*(?!\w)', dotAll: true));
    out = unwrap(out, RegExp(r'(?<!\w)_(\S(?:.*?\S)?)_(?!\w)', dotAll: true));
    // `code`
    out = unwrap(out, RegExp(r'`([^`]+)`'));

    return out.trim();
  }

  /// Deterministic fallback used when no AI provider is reachable.
  ///
  /// Everything here comes from [CareAnalytics], so the app still gives the
  /// owner a genuine, data-driven daily summary with no network at all.
  static String offlineDailyBrief({
    required String petName,
    required PetContext context,
  }) {
    final TodaySnapshot s = context.snapshot;
    final List<String> lines = <String>[];

    if (s.feedingsScheduled == 0) {
      lines.add('No feeding schedule is set up for $petName yet.');
    } else if (s.allFeedingsDone) {
      lines.add(
          'All ${s.feedingsScheduled} scheduled feedings are done for today.');
    } else {
      lines.add(
          '${s.feedingsCompleted} of ${s.feedingsScheduled} feedings completed'
          '${s.pendingFeedings.isEmpty ? '' : ' — ${s.pendingFeedings.first.label} '
              'at ${s.pendingFeedings.first.timeLabel} is still due'}.');
    }

    lines.add(s.hasExercise
        ? '${s.exerciseMinutes} minutes of exercise recorded today.'
        : 'No exercise recorded today yet.');

    if (s.dosesDue > 0) {
      lines.add('${s.dosesTaken} of ${s.dosesDue} medication doses given today.');
    }

    if (s.nextAppointment != null) {
      lines.add('Vet appointment: ${s.nextAppointment!.whenLabel}.');
    }

    if (context.anomalies.isNotEmpty) {
      lines.add(context.anomalies.first.title.toLowerCase() == 'activity lower than usual'
          ? 'Recorded activity is below this pet\'s recent average.'
          : context.anomalies.first.title);
    }

    return lines.join(' ');
  }
}

/// Fire-and-forget helper; keeps the intent explicit at each call site.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    if (kDebugMode) debugPrint('unawaited future failed: $e');
  });
}
