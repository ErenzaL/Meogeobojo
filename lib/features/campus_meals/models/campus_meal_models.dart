import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../l10n/app_localizations.dart';
import '../utils/seoul_date.dart';

enum MealType {
  breakfast('breakfast'),
  lunch('lunch'),
  dinner('dinner');

  const MealType(this.dbValue);
  final String dbValue;

  static MealType? fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
    breakfast => l10n.mealBreakfast,
    lunch => l10n.mealLunch,
    dinner => l10n.mealDinner,
  };
}

/// What the source says about a meal. A *missing* row is not a status: it
/// means the data has not been collected yet.
enum MealStatus {
  published,

  /// The source states the cafeteria does not serve this meal.
  closed,

  /// The source states that no menu is published.
  noMenu;

  static MealStatus? fromDb(String? v) => switch (v) {
    'published' => published,
    'closed' => closed,
    'no_menu' => noMenu,
    _ => null,
  };
}

enum CafeteriaKind {
  student('student'),
  dormitory('dormitory'),
  staff('staff'),
  other('other');

  const CafeteriaKind(this.dbValue);
  final String dbValue;

  static CafeteriaKind fromDb(String? v) {
    for (final k in values) {
      if (k.dbValue == v) return k;
    }
    return other;
  }

  String label(AppLocalizations l10n) => switch (this) {
    student => l10n.mealKindStudent,
    dormitory => l10n.mealKindDormitory,
    staff => l10n.mealKindStaff,
    other => l10n.mealKindOther,
  };
}

@immutable
class CampusCafeteria {
  const CampusCafeteria({
    required this.id,
    required this.universityId,
    required this.kind,
    this.nameKo,
    this.nameEn,
    this.nameZh,
    this.locationDescription,
  });

  final String id;
  final String universityId;
  final CafeteriaKind kind;
  final String? nameKo;
  final String? nameEn;
  final String? nameZh;
  final String? locationDescription;

  factory CampusCafeteria.fromJson(Map<String, dynamic> j) => CampusCafeteria(
    id: j['id'] as String,
    universityId: j['university_id'] as String,
    kind: CafeteriaKind.fromDb(j['kind'] as String?),
    nameKo: j['name_ko'] as String?,
    nameEn: j['name_en'] as String?,
    nameZh: j['name_zh'] as String?,
    locationDescription: j['location_description'] as String?,
  );

  /// The official name in the active language when a verified translation
  /// exists, else the Korean original; null when no name is known at all.
  String? officialName(Locale locale) {
    final translated = switch (locale.languageCode) {
      'en' => nameEn,
      'zh' => nameZh,
      _ => null,
    };
    final v = (translated?.trim().isNotEmpty ?? false) ? translated : nameKo;
    return (v?.trim().isNotEmpty ?? false) ? v!.trim() : null;
  }

  @override
  bool operator ==(Object other) => other is CampusCafeteria && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Label for [cafeteria] inside [all]: its official name, otherwise its
/// category ("학생식당"), numbered when several nameless ones share a category.
/// Never an invented name.
String cafeteriaLabel(
  AppLocalizations l10n,
  Locale locale,
  CampusCafeteria cafeteria,
  List<CampusCafeteria> all,
) {
  final name = cafeteria.officialName(locale);
  if (name != null) return name;
  final sameKind = all
      .where((c) => c.kind == cafeteria.kind && c.officialName(locale) == null)
      .toList();
  final base = cafeteria.kind.label(l10n);
  if (sameKind.length < 2) return base;
  return l10n.mealCafeteriaNth(base, sameKind.indexOf(cafeteria) + 1);
}

enum MenuItemKind { main, side, soup, rice, other }

@immutable
class MenuItem {
  const MenuItem({
    required this.nameKo,
    this.nameEn,
    this.nameZh,
    this.kind = MenuItemKind.other,
  });

  final String nameKo;
  final String? nameEn;
  final String? nameZh;
  final MenuItemKind kind;

  /// Items arrive as objects ({name_ko, name_en, name_zh, kind}) or plain
  /// strings. Anything unusable is skipped, never guessed.
  static MenuItem? fromJson(Object? j) {
    if (j is String && j.trim().isNotEmpty) return MenuItem(nameKo: j.trim());
    if (j is Map) {
      final ko = (j['name_ko'] as String?)?.trim();
      if (ko == null || ko.isEmpty) return null;
      String? opt(String k) {
        final v = (j[k] as String?)?.trim();
        return (v == null || v.isEmpty) ? null : v;
      }

      return MenuItem(
        nameKo: ko,
        nameEn: opt('name_en'),
        nameZh: opt('name_zh'),
        kind: MenuItemKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => MenuItemKind.other,
        ),
      );
    }
    return null;
  }

  /// Official menu names are not machine-translated: a verified translation
  /// is shown if present, otherwise the Korean original.
  String displayName(Locale locale) => switch (locale.languageCode) {
    'en' => nameEn ?? nameKo,
    'zh' => nameZh ?? nameKo,
    _ => nameKo,
  };
}

@immutable
class CafeteriaMeal {
  const CafeteriaMeal({
    required this.id,
    required this.cafeteriaId,
    required this.date,
    required this.type,
    required this.optionName,
    required this.optionOrder,
    required this.items,
    required this.status,
    required this.verifiedAt,
    this.priceKrw,
    this.startTime,
    this.endTime,
    this.sourceUrl,
    this.badge,
    this.photoUrl,
    this.notice,
  });

  final String id;
  final String cafeteriaId;
  final DateTime date;
  final MealType type;

  /// '' for the single/default option; e.g. "B코너" for a second choice.
  final String optionName;
  final int optionOrder;
  final List<MenuItem> items;
  final MealStatus status;
  final int? priceKrw;

  /// "HH:mm" strings, only present when verified.
  final String? startTime;
  final String? endTime;
  final String? sourceUrl;

  /// Program label such as "천원의 아침밥", set by an admin only when the
  /// source says so.
  final String? badge;
  final DateTime verifiedAt;

  /// Admin-uploaded photo of the meal (`extra.photo_url`, https only).
  final String? photoUrl;

  /// Admin-written note for this meal (`extra.notice`).
  final String? notice;

  static CafeteriaMeal? fromJson(Map<String, dynamic> j) {
    final type = MealType.fromDb(j['meal_type'] as String?);
    final status = MealStatus.fromDb(j['status'] as String?);
    if (type == null || status == null) return null;
    String? hhmm(Object? v) {
      final s = v as String?;
      return (s == null || s.length < 5) ? null : s.substring(0, 5);
    }

    final extra = j['extra'] is Map ? j['extra'] as Map : const {};
    String? text(Object? v) {
      final t = (v as String?)?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final photo = text(extra['photo_url']);
    return CafeteriaMeal(
      id: j['id'] as String,
      cafeteriaId: j['cafeteria_id'] as String,
      date: parseIsoDate(j['meal_date'] as String),
      type: type,
      optionName: (j['option_name'] as String?) ?? '',
      optionOrder: (j['option_order'] as num?)?.toInt() ?? 0,
      items: (j['menu_items'] as List<dynamic>? ?? const [])
          .map(MenuItem.fromJson)
          .whereType<MenuItem>()
          .toList(),
      status: status,
      priceKrw: (j['price_krw'] as num?)?.toInt(),
      startTime: hhmm(j['start_time']),
      endTime: hhmm(j['end_time']),
      sourceUrl: j['source_url'] as String?,
      badge: (j['badge'] as String?)?.trim().isEmpty ?? true
          ? null
          : (j['badge'] as String).trim(),
      verifiedAt: DateTime.parse(j['verified_at'] as String),
      photoUrl: (photo != null && photo.startsWith('https://')) ? photo : null,
      notice: text(extra['notice']),
    );
  }
}

/// One cafeteria's meals for one Monday-Sunday week, indexed for the screen.
@immutable
class WeekMeals {
  const WeekMeals(this.weekStart, this.meals);

  final DateTime weekStart;
  final List<CafeteriaMeal> meals;

  bool get isEmpty => meals.isEmpty;

  /// All options for [date] and [type], in the order the source gave them.
  List<CafeteriaMeal> options(DateTime date, MealType type) {
    final r = meals.where((m) => m.date == date && m.type == type).toList()
      ..sort((a, b) {
        final c = a.optionOrder.compareTo(b.optionOrder);
        return c != 0 ? c : a.optionName.compareTo(b.optionName);
      });
    return r;
  }

  /// Most recent verification among the given meals.
  static DateTime? latestVerification(Iterable<CafeteriaMeal> meals) {
    DateTime? latest;
    for (final m in meals) {
      if (latest == null || m.verifiedAt.isAfter(latest)) latest = m.verifiedAt;
    }
    return latest;
  }
}
