import 'package:flutter/foundation.dart';

enum ContributionKind {
  restaurantPhoto('restaurant_photo'),
  menuPhoto('menu_photo');

  const ContributionKind(this.db);
  final String db;

  static ContributionKind? fromDb(Object? v) =>
      values.where((k) => k.db == v).firstOrNull;
}

/// One of the signed-in user's photo submissions (`user_contributions`).
@immutable
class Contribution {
  const Contribution({
    required this.id,
    required this.kind,
    required this.kakaoPlaceId,
    required this.status,
    required this.createdAt,
    this.caption,
    this.path,
    this.reviewNote,
  });

  final String id;
  final ContributionKind kind;
  final String kakaoPlaceId;

  /// pending | approved | rejected
  final String status;
  final DateTime createdAt;
  final String? caption;

  /// Where the private picture is stored (only until it is reviewed).
  final String? path;
  final String? reviewNote;

  bool get isPending => status == 'pending';

  /// Photo kinds only: a correction suggestion is not a photo submission.
  static Contribution? fromJson(Map<String, dynamic> j) {
    final kind = ContributionKind.fromDb(j['kind']);
    final id = j['id'] as String?;
    final place = j['kakao_place_id'] as String?;
    final created = DateTime.tryParse('${j['created_at']}');
    if (kind == null || id == null || place == null || created == null) {
      return null;
    }
    final payload = j['payload'] is Map ? j['payload'] as Map : const {};
    String? text(Object? v) {
      final t = (v as String?)?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return Contribution(
      id: id,
      kind: kind,
      kakaoPlaceId: place,
      status: (j['status'] as String?) ?? 'pending',
      createdAt: created,
      caption: text(payload['caption']),
      path: text(payload['path']),
      reviewNote: text(j['review_note']),
    );
  }
}

/// A picture chosen on the device, already limited in size.
@immutable
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.mime,
    required this.name,
  });

  final Uint8List bytes;
  final String mime;
  final String name;

  String get extension => switch (mime) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
}

const maxPhotoBytes = 5 * 1024 * 1024;
const allowedPhotoTypes = ['image/jpeg', 'image/png', 'image/webp'];

/// Why a submission was refused before or after upload.
enum ContributionError { tooLarge, badType, duplicate, tooMany, failed }

class ContributionException implements Exception {
  const ContributionException(this.error);
  final ContributionError error;

  @override
  String toString() => 'ContributionException($error)';
}
