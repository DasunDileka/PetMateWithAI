import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firestore_refs.dart';
import '../../shared/models/ai_models.dart';
import '../pets/pet_repository.dart' show DataFailure;

/// Persistence for AI chat sessions and their messages.
///
/// Sessions are user-scoped rather than pet-scoped so a conversation stays
/// readable after the user switches active pet; the pet it was about is
/// denormalised onto the session.
class ChatRepository {
  const ChatRepository(this.uid);

  final String uid;

  /// Recent conversations, newest activity first.
  Stream<List<ChatSession>> watchSessions({int limit = 30}) {
    return Refs.chatSessions(uid)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ChatSession.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  /// Messages in a session, oldest first so the list renders top-to-bottom.
  Stream<List<ChatMessage>> watchMessages(String sessionId, {int limit = 100}) {
    return Refs.chatMessages(uid, sessionId)
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ChatMessage.fromMap(d.id, d.data()))
            .toList(growable: false))
        .handleError((Object e) => throw DataFailure.from(e));
  }

  Future<ChatSession> createSession({
    String? petId,
    String? petName,
    String title = 'New conversation',
  }) async {
    try {
      final DateTime now = DateTime.now();
      final ChatSession session = ChatSession(
        id: '',
        title: title,
        createdAt: now,
        updatedAt: now,
        petId: petId,
        petName: petName,
      );

      final DocumentReference<Map<String, dynamic>> ref =
          await Refs.chatSessions(uid).add(session.toMap());

      return ChatSession(
        id: ref.id,
        title: title,
        createdAt: now,
        updatedAt: now,
        petId: petId,
        petName: petName,
      );
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Appends a message and updates the session summary atomically, so the
  /// session list preview can never drift from the actual last message.
  Future<void> addMessage(String sessionId, ChatMessage message) async {
    try {
      final WriteBatch batch = Refs.db.batch();

      batch.set(
        Refs.chatMessages(uid, sessionId).doc(),
        message.toMap(),
      );

      batch.set(
        Refs.chatSessions(uid).doc(sessionId),
        <String, dynamic>{
          'updatedAt': message.createdAt,
          'messageCount': FieldValue.increment(1),
          if (!message.isError)
            'lastMessagePreview': _preview(message.text),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Names a session from its first user message, so the history list is
  /// browsable without opening each thread.
  Future<void> titleFromFirstMessage(String sessionId, String question) async {
    try {
      await Refs.chatSessions(uid).doc(sessionId).set(
        <String, dynamic>{'title': _preview(question, max: 48)},
        SetOptions(merge: true),
      );
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Deletes a session and its messages.
  Future<void> deleteSession(String sessionId) async {
    try {
      while (true) {
        final QuerySnapshot<Map<String, dynamic>> snap =
            await Refs.chatMessages(uid, sessionId).limit(200).get();
        if (snap.docs.isEmpty) break;

        final WriteBatch batch = Refs.db.batch();
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();

        if (snap.docs.length < 200) break;
      }

      await Refs.chatSessions(uid).doc(sessionId).delete();
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  /// Clears every conversation — offered on the profile screen as a plain
  /// data-control action.
  Future<void> deleteAllSessions() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> sessions =
          await Refs.chatSessions(uid).get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> s in sessions.docs) {
        await deleteSession(s.id);
      }
    } catch (e) {
      throw DataFailure.from(e);
    }
  }

  static String _preview(String text, {int max = 80}) {
    final String clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length <= max ? clean : '${clean.substring(0, max - 1)}…';
  }
}
