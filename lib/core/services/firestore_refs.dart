import 'package:cloud_firestore/cloud_firestore.dart';

/// Every Firestore path in PetMate, in one place.
///
/// Paths are the contract between the client and the security rules. Building
/// them here rather than as scattered string literals means a rule change has
/// exactly one place to check against, and no feature can accidentally read
/// outside the signed-in user's subtree.
class Refs {
  const Refs._();

  static FirebaseFirestore get db => FirebaseFirestore.instance;

  // ------------------------------------------------------------------ user
  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      db.collection('users').doc(uid);

  static CollectionReference<Map<String, dynamic>> pets(String uid) =>
      user(uid).collection('pets');

  static DocumentReference<Map<String, dynamic>> pet(String uid, String petId) =>
      pets(uid).doc(petId);

  // ---------------------------------------------------------- care records
  static CollectionReference<Map<String, dynamic>> feedingSchedules(
          String uid, String petId) =>
      pet(uid, petId).collection('feedingSchedules');

  static CollectionReference<Map<String, dynamic>> feedingRecords(
          String uid, String petId) =>
      pet(uid, petId).collection('feedingRecords');

  static CollectionReference<Map<String, dynamic>> exercise(
          String uid, String petId) =>
      pet(uid, petId).collection('exerciseRecords');

  static CollectionReference<Map<String, dynamic>> medicines(
          String uid, String petId) =>
      pet(uid, petId).collection('medicines');

  static CollectionReference<Map<String, dynamic>> medicineDoses(
          String uid, String petId) =>
      pet(uid, petId).collection('medicineDoses');

  static CollectionReference<Map<String, dynamic>> vaccinations(
          String uid, String petId) =>
      pet(uid, petId).collection('vaccinations');

  static CollectionReference<Map<String, dynamic>> grooming(
          String uid, String petId) =>
      pet(uid, petId).collection('groomingRecords');

  static CollectionReference<Map<String, dynamic>> appointments(
          String uid, String petId) =>
      pet(uid, petId).collection('appointments');

  static CollectionReference<Map<String, dynamic>> medicalHistory(
          String uid, String petId) =>
      pet(uid, petId).collection('medicalHistory');

  static CollectionReference<Map<String, dynamic>> aiInsights(
          String uid, String petId) =>
      pet(uid, petId).collection('aiInsights');

  // -------------------------------------------------- user-level resources
  /// Vets live at user level: one clinic normally serves every pet in a home.
  static CollectionReference<Map<String, dynamic>> veterinarians(String uid) =>
      user(uid).collection('veterinarians');

  static CollectionReference<Map<String, dynamic>> chatSessions(String uid) =>
      user(uid).collection('chatSessions');

  static CollectionReference<Map<String, dynamic>> chatMessages(
          String uid, String sessionId) =>
      chatSessions(uid).doc(sessionId).collection('messages');

  static DocumentReference<Map<String, dynamic>> settings(
          String uid, String name) =>
      user(uid).collection('settings').doc(name);
}
