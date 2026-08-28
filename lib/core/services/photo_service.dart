import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Result of a photo operation. Photos are a convenience, never a blocker: a
/// failure here must not stop the user saving the pet itself.
class PhotoResult {
  const PhotoResult.success(this.downloadUrl)
      : error = null,
        cancelled = false;

  const PhotoResult.failure(this.error)
      : downloadUrl = null,
        cancelled = false;

  const PhotoResult.cancelled()
      : downloadUrl = null,
        error = null,
        cancelled = true;

  final String? downloadUrl;
  final String? error;
  final bool cancelled;

  bool get isSuccess => downloadUrl != null;
}

/// Captures pet and profile photos and stores them in Cloud Storage.
///
/// Images are downscaled and re-encoded on the device before upload. A modern
/// phone camera produces 4–8 MB files; at 1024 px and 80% JPEG quality the same
/// image is typically under 200 KB. That keeps uploads fast on poor connections
/// and keeps the app inside the 5 MB limit the Storage rules enforce.
class PhotoService {
  PhotoService({ImagePicker? picker, FirebaseStorage? storage})
      : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FirebaseStorage.instance;

  final ImagePicker _picker;
  final FirebaseStorage _storage;

  static const int _maxDimension = 1024;
  static const int _quality = 80;

  Future<PhotoResult> pickAndUploadPetPhoto({
    required String uid,
    required String petId,
    required ImageSource source,
  }) async {
    return _pickAndUpload(
      source: source,
      path: 'users/$uid/pets/$petId/photo.jpg',
    );
  }

  Future<PhotoResult> pickAndUploadProfilePhoto({
    required String uid,
    required ImageSource source,
  }) async {
    return _pickAndUpload(
      source: source,
      path: 'users/$uid/profile/avatar.jpg',
    );
  }

  Future<PhotoResult> _pickAndUpload({
    required ImageSource source,
    required String path,
  }) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: _maxDimension.toDouble(),
        maxHeight: _maxDimension.toDouble(),
        imageQuality: _quality,
      );

      if (file == null) return const PhotoResult.cancelled();

      final File local = File(file.path);
      final int bytes = await local.length();

      // Belt and braces: the picker should already have shrunk this, but a
      // rejected upload is a worse experience than an early, clear message.
      if (bytes > 5 * 1024 * 1024) {
        return const PhotoResult.failure(
          'That image is too large. Please choose a smaller photo.',
        );
      }

      final Reference ref = _storage.ref(path);
      await ref.putFile(
        local,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      return PhotoResult.success(await ref.getDownloadURL());
    } on FirebaseException catch (e) {
      if (kDebugMode) debugPrint('photo upload failed: ${e.code}');
      return PhotoResult.failure(switch (e.code) {
        'unauthorized' || 'permission-denied' =>
          'You do not have permission to upload this photo.',
        'canceled' => 'Upload cancelled.',
        'object-not-found' => 'That photo could not be found.',
        'quota-exceeded' =>
          'Photo storage is unavailable on this project. The pet was saved '
              'without a photo.',
        'unknown' =>
          'Photo storage is not enabled for this project. The pet was saved '
              'without a photo.',
        _ => 'Could not upload the photo. Please try again.',
      });
    } catch (e) {
      if (kDebugMode) debugPrint('photo pick failed: $e');
      return const PhotoResult.failure(
        'Could not access photos on this device.',
      );
    }
  }

  /// Removes a stored photo. A missing object is treated as success — the
  /// caller's intent (no photo) is already satisfied.
  Future<void> deletePetPhoto({
    required String uid,
    required String petId,
  }) async {
    try {
      await _storage.ref('users/$uid/pets/$petId/photo.jpg').delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found' && kDebugMode) {
        debugPrint('photo delete failed: ${e.code}');
      }
    }
  }
}
