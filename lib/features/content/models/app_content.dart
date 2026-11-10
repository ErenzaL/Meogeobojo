import 'package:flutter/foundation.dart';

enum AppContentKind { announcement, banner, featured }

/// One live item an admin published (`app_content`): a notice, a banner or a
/// featured restaurant. RLS only returns items that are switched on and inside
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
    );
  }
}
