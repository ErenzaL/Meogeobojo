import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contribution.dart';

/// Chooses a picture on the device. Behind an interface so tests do not need
/// the platform picker.
abstract interface class PhotoPicker {
  /// Null when the user cancels.
  Future<PickedPhoto?> pick();
}

class ImagePickerPhotoPicker implements PhotoPicker {
  @override
  Future<PickedPhoto?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Phone photos are large: shrink them before upload (also keeps them
      // under the 5 MB limit of the storage bucket).
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return PickedPhoto(bytes: bytes, mime: mime, name: file.name);
  }
}

abstract interface class ContributionRepository {
  /// Uploads [photo] to the PRIVATE bucket (the user's own folder) and submits
  /// it for review. Nothing is left in storage if the submission is refused.
  Future<void> submitPhoto({
    required String userId,
    required ContributionKind kind,
    required String kakaoPlaceId,
    required PickedPhoto photo,
    String? caption,
  });

  Future<List<Contribution>> mine(String userId);

  /// Withdraws a PENDING submission and deletes its private picture.
  Future<void> withdraw(Contribution c);
}

class SupabaseContributionRepository implements ContributionRepository {
  SupabaseContributionRepository(this._db);

  final SupabaseClient _db;
  static const bucket = 'contribution-photos';

  String _fileName(String ext) {
    final r = Random.secure();
    final id = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$id.$ext';
  }

  @override
  Future<void> submitPhoto({
    required String userId,
    required ContributionKind kind,
    required String kakaoPlaceId,
    required PickedPhoto photo,
    String? caption,
  }) async {
    if (!allowedPhotoTypes.contains(photo.mime)) {
      throw const ContributionException(ContributionError.badType);
    }
    if (photo.bytes.length > maxPhotoBytes) {
      throw const ContributionException(ContributionError.tooLarge);
    }
    final path = '$userId/${_fileName(photo.extension)}';
    try {
      await _db.storage
          .from(bucket)
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(contentType: photo.mime, upsert: false),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      debugPrint('photo upload failed: ${e.runtimeType}');
      throw const ContributionException(ContributionError.failed);
    }
    try {
      final cap = caption?.trim();
      await _db
          .rpc<dynamic>(
            'submit_contribution',
            params: {
              'p_kind': kind.db,
              'p_place': kakaoPlaceId,
              'p_payload': {
                'path': path,
                'consent': true,
                if (cap != null && cap.isNotEmpty) 'caption': cap,
              },
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      // The picture is useless without its record: do not leave it behind.
      try {
        await _db.storage.from(bucket).remove([path]);
      } catch (_) {}
      if (e is PostgrestException) {
        if (e.code == '23505') {
          throw const ContributionException(ContributionError.duplicate);
        }
        if (e.code == '54000') {
          throw const ContributionException(ContributionError.tooMany);
        }
      }
      debugPrint('contribution rejected: ${e.runtimeType}');
      throw const ContributionException(ContributionError.failed);
    }
  }

  @override
  Future<List<Contribution>> mine(String userId) async {
    final rows = await _db
        .from('user_contributions')
        .select('id,kind,kakao_place_id,payload,status,review_note,created_at')
        .eq('user_id', userId)
        .inFilter('kind', [for (final k in ContributionKind.values) k.db])
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 12));
    return [for (final r in rows) ?Contribution.fromJson(r)];
  }

  @override
  Future<void> withdraw(Contribution c) async {
    final path = await _db
        .rpc<dynamic>('delete_my_contribution', params: {'p_id': c.id})
        .timeout(const Duration(seconds: 20));
    final p = (path is String && path.isNotEmpty) ? path : c.path;
    if (p != null) {
      try {
        await _db.storage.from(bucket).remove([p]);
      } catch (_) {
        // The row is gone; a leftover private file is invisible to everyone but staff.
      }
    }
  }
}
