import '../../core/utils/field_mapper.dart';

/// The kinds of generated output PetMate persists.
enum AiInsightKind {
  dailyBrief,
  trend,
  anomaly,
  vetSummary;

  String get label => switch (this) {
        AiInsightKind.dailyBrief => 'Daily Care Insight',
        AiInsightKind.trend => 'Activity Trend',
        AiInsightKind.anomaly => 'Pattern Alert',
        AiInsightKind.vetSummary => 'Vet Visit Summary',
      };
}

/// Which transport produced a response. Surfaced in the UI so the fallback
/// path is demonstrable rather than invisible.
enum AiProvider {
  gemini,
  openRouter,
  gateway,
  local;

  String get label => switch (this) {
        AiProvider.gemini => 'Gemini',
        AiProvider.openRouter => 'OpenRouter',
        AiProvider.gateway => 'PetMate Gateway',
        AiProvider.local => 'On-device analysis',
      };
}

/// A generated insight, cached in Firestore so reopening a screen does not
/// trigger a fresh model call.
/// Stored at `users/{uid}/pets/{petId}/aiInsights/{id}`.
class AiInsight {
  const AiInsight({
    required this.id,
    required this.kind,
    required this.text,
    required this.generatedAt,
    required this.provider,
    this.model,
    this.contextFingerprint,
    this.latencyMs,
  });

  final String id;
  final AiInsightKind kind;
  final String text;
  final DateTime generatedAt;
  final AiProvider provider;
  final String? model;

  /// Hash of the pet data the insight was built from. When the underlying data
  /// changes the fingerprint changes, which is how the app knows a cached
  /// insight is stale without calling the model to find out.
  final String? contextFingerprint;

  final int? latencyMs;

  bool isFreshFor(Duration ttl) =>
      DateTime.now().difference(generatedAt) < ttl;

  /// Cached output is reusable only when it is both recent *and* built from
  /// the same underlying data.
  bool matches(String fingerprint, Duration ttl) =>
      contextFingerprint == fingerprint && isFreshFor(ttl);

  factory AiInsight.fromMap(String id, Map<String, dynamic> map) {
    return AiInsight(
      id: id,
      kind: readEnum(
        map['kind'],
        AiInsightKind.values,
        AiInsightKind.dailyBrief,
        (e) => e.name,
      ),
      text: readString(map['text']),
      generatedAt: readDate(map['generatedAt'], fallback: DateTime.now()),
      provider: readEnum(
        map['provider'],
        AiProvider.values,
        AiProvider.gemini,
        (e) => e.name,
      ),
      model: readStringOrNull(map['model']),
      contextFingerprint: readStringOrNull(map['contextFingerprint']),
      latencyMs: map['latencyMs'] == null ? null : readInt(map['latencyMs']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'kind': kind.name,
        'text': text,
        'generatedAt': generatedAt,
        'provider': provider.name,
        'model': model,
        'contextFingerprint': contextFingerprint,
        'latencyMs': latencyMs,
      });
}

enum ChatRole { user, assistant }

/// One chat turn.
/// Stored at `users/{uid}/chatSessions/{sessionId}/messages/{id}`.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.provider,
    this.isError = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final AiProvider? provider;

  /// Error turns are rendered differently and are never sent back to the model
  /// as conversation history.
  final bool isError;

  bool get isUser => role == ChatRole.user;

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChatMessage(
      id: id,
      role: readEnum(map['role'], ChatRole.values, ChatRole.user, (e) => e.name),
      text: readString(map['text']),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
      provider: map['provider'] == null
          ? null
          : readEnum<AiProvider>(
              map['provider'],
              AiProvider.values,
              AiProvider.gemini,
              (e) => e.name,
            ),
      isError: readBool(map['isError']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'role': role.name,
        'text': text,
        'createdAt': createdAt,
        'provider': provider?.name,
        'isError': isError,
      });
}

/// A conversation thread.
/// Stored at `users/{uid}/chatSessions/{id}`.
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.petId,
    this.petName,
    this.messageCount = 0,
    this.lastMessagePreview,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Which pet the conversation was about, so history stays interpretable
  /// after the user switches active pet.
  final String? petId;
  final String? petName;

  final int messageCount;
  final String? lastMessagePreview;

  factory ChatSession.fromMap(String id, Map<String, dynamic> map) {
    return ChatSession(
      id: id,
      title: readString(map['title'], fallback: 'New conversation'),
      createdAt: readDate(map['createdAt'], fallback: DateTime.now()),
      updatedAt: readDate(map['updatedAt'], fallback: DateTime.now()),
      petId: readStringOrNull(map['petId']),
      petName: readStringOrNull(map['petName']),
      messageCount: readInt(map['messageCount']),
      lastMessagePreview: readStringOrNull(map['lastMessagePreview']),
    );
  }

  Map<String, dynamic> toMap() => pruneNulls(<String, dynamic>{
        'title': title.trim(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'petId': petId,
        'petName': petName,
        'messageCount': messageCount,
        'lastMessagePreview': lastMessagePreview,
      });

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    int? messageCount,
    String? lastMessagePreview,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      petId: petId,
      petName: petName,
      messageCount: messageCount ?? this.messageCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    );
  }
}

/// Normalised result returned by the AI service layer, regardless of which
/// provider actually served the request.
class AiResult {
  const AiResult({
    required this.text,
    required this.provider,
    this.model,
    this.latencyMs,
    this.fromCache = false,
  });

  final String text;
  final AiProvider provider;
  final String? model;
  final int? latencyMs;
  final bool fromCache;
}

/// Raised by the AI layer with a message that is always safe to show a user.
class AiException implements Exception {
  const AiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
