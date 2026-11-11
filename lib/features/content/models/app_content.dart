import 'package:flutter/foundation.dart';

enum AppContentKind { announcement, banner, featured, notification }

/// One live item an admin published (`app_content`): a notice, a banner, a
/// featured restaurant or a notification (bell only). RLS only returns items that are switched on and inside
/// their date window, so everything here is meant to be shown.
@immutable
class AppContent {
  const AppContent({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.imageUrl,
    this.linkUrl,
    this.kakaoPlaceId,
    this.universityId,
    this.sortOrder = 0,
    this.time,
  });

  final String id;
  final AppContentKind kind;
  final String title;
  final String? body;
  final String? imageUrl;
  final String? linkUrl;
  final String? kakaoPlaceId;

  /// Null = every campus.
  final String? universityId;
  final int sortOrder;

  /// When it went live (its start time if it has one, else when it was last
  /// published): what the bell shows and sorts by. Null if the server sent none.
  final DateTime? time;

  static AppContent? fromJson(Map<String, dynamic> j) {
    final kind = AppContentKind.values
        .where((k) => k.name == j['kind'])
        .firstOrNull;
    final title = (j['title'] as String?)?.trim();
    final id = j['id'] as String?;
    if (kind == null || title == null || title.isEmpty || id == null) {
      return null;
    }
    String? text(Object? v) {
      final t = (v as String?)?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    String? https(Object? v) {
      final t = text(v);
      return (t != null && t.startsWith('https://')) ? t : null;
    }

    return AppContent(
      id: id,
      kind: kind,
      title: title,
      body: text(j['body']),
      imageUrl: https(j['image_url']),
      linkUrl: https(j['link_url']),
      kakaoPlaceId: text(j['kakao_place_id']),
      universityId: text(j['university_id']),
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      time:
          _time(j['starts_at']) ??
          _time(j['updated_at']) ??
          _time(j['created_at']),
    );
  }

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}
