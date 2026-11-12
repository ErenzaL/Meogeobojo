import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../l10n/app_localizations.dart';
import '../utils/seoul_date.dart';

/// The special breakfast programme's name, exactly as the Admin stores it in `badge`.
const thousandWonBreakfast = '천원의 아침밥';

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
    this.operatingNote,
    this.mealTypes = MealType.values,
    this.operatingDays = const {1, 2, 3, 4, 5},
    this.photoUrl,
  });

  final String id;
  final String universityId;
  final CafeteriaKind kind;
  final String? nameKo;
  final String? nameEn;
  final String? nameZh;
  final String? locationDescription;

  /// Operating information an admin confirmed (`operating_note`).
  final String? operatingNote;

  /// The meals this cafeteria serves (never assumed to be all three) and the
  /// ISO weekdays it is open (1 = Monday ... 7 = Sunday). A database without
  /// these columns reports all three meals on Monday-Friday.
  final List<MealType> mealTypes;
  final Set<int> operatingDays;

  /// Photo of the cafeteria (https only).
  final String? photoUrl;

  bool serves(MealType t) => mealTypes.contains(t);

  /// Saturday / Sunday are shown only for a cafeteria that opens then.
  bool get opensAtWeekend => operatingDays.any((d) => d >= 6);

  factory CampusCafeteria.fromJson(Map<String, dynamic> j) => CampusCafeteria(
    id: j['id'] as String,
    universityId: j['university_id'] as String,
    kind: CafeteriaKind.fromDb(j['kind'] as String?),
    nameKo: j['name_ko'] as String?,
    nameEn: j['name_en'] as String?,
    nameZh: j['name_zh'] as String?,
    locationDescription: j['location_description'] as String?,
    operatingNote: (j['operating_note'] as String?)?.trim().isEmpty ?? true
        ? null
        : (j['operating_note'] as String).trim(),
    mealTypes: _mealTypes(j['meal_periods']),
    operatingDays: _days(j['operating_days']),
    photoUrl: _https(j['photo_url']),
  );

  static List<MealType> _mealTypes(Object? v) {
    final list = [
      if (v is List)
        for (final x in v) ?MealType.fromDb(x as String?),
    ];
    return list.isEmpty
        ? MealType.values
        : [
            for (final t in MealType.values)
              if (list.contains(t)) t,
          ];
  }

  static Set<int> _days(Object? v) {
    final days = {
      if (v is List)
        for (final x in v)
          if (x is num && x >= 1 && x <= 7) x.toInt(),
    };
    return days.isEmpty ? const {1, 2, 3, 4, 5} : days;
  }

  static String? _https(Object? v) {
    final t = (v as String?)?.trim();
    return (t != null && t.startsWith('https://')) ? t : null;
  }

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

/// The cafeteria to show: the user's [pick] when it still belongs to [all],
/// otherwise the first student cafeteria, otherwise the first one. Null only
/// when the campus has none. Home and the weekly page share this rule.
CampusCafeteria? chooseCafeteria(List<CampusCafeteria> all, String? pick) {
  if (all.isEmpty) return null;
  for (final c in all) {
    if (c.id == pick) return c;
  }
  return all.firstWhere(
    (c) => c.kind == CafeteriaKind.student,
    orElse: () => all.first,
  );
}

/// The meal tabs of a week: only meals an admin actually entered (any status,
/// so a meal marked closed still explains itself). Nothing is assumed, so a
/// cafeteria that only serves lunch shows one tab. A week with no meals at all
/// (or one not loaded) falls back to what the cafeteria is set up to serve.
List<MealType> visibleMealTypes(CampusCafeteria cafeteria, WeekMeals? week) {
  if (week == null || week.isEmpty) return cafeteria.mealTypes;
  return [
    for (final t in MealType.values)
      if (week.meals.any((m) => m.type == t)) t,
  ];
}

/// [wanted] when it is one of [types], otherwise the next meal of the day that
/// is, otherwise the last one (so a missing breakfast opens on lunch, a missing
/// dinner on lunch).
MealType resolveMealType(MealType wanted, List<MealType> types) {
  if (types.contains(wanted)) return wanted;
  for (final t in MealType.values) {
    if (t.index > wanted.index && types.contains(t)) return t;
  }
  return types.last;
}

/// Dish categories. An older app version that does not know a newer category
/// shows the dish as `other`, so adding categories never breaks installed apps.
enum MenuItemKind {
  main,
  side,
  soup,
  rice,
  kimchi,
  salad,
  dessert,
  drink,
  other,
}

@immutable
class MenuItem {
  const MenuItem({
    required this.nameKo,
    this.nameEn,
    this.nameZh,
    this.kind = MenuItemKind.other,
    this.shared = false,
  });

  final String nameKo;
  final String? nameEn;
  final String? nameZh;
  final MenuItemKind kind;

  /// A dish that comes with every menu of the day (rice, kimchi, salad ...).
  final bool shared;

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
        shared: j['shared'] == true,
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
    this.description,
    this.soldOut = false,
    this.origin,
    this.dietaryLabels = const [],
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

  /// Short description (`extra.description`) and the admin's sold-out flag (`extra.sold_out`).
  final String? description;
  final bool soldOut;

  /// Ingredient origin statement (`extra.origin`, 원산지 표시사항).
  final String? origin;

  /// Dietary labels such as HALAL (`extra.labels`). Present ONLY when the admin
  /// confirmed them from an official source (`extra.labels_verified == true`).
  final List<String> dietaryLabels;

  static const _knownLabels = {'HALAL', 'VEGETARIAN', 'VEGAN'};

  static CafeteriaMeal? fromJson(Map<String, dynamic> j) {
    final type = MealType.fromDb(j['meal_type'] as String?);
    final status = MealStatus.fromDb(j['status'] as String?);
    if (type == null || status == null) return null;
    String? hhmm(Object? v) {
      final s = v as String?;
      return (s == null || s.length < 5) ? null : s.substring(0, 5);
    }

    final extra = j['extra'] is Map ? j['extra'] as Map : const {};
    // `extra` is free-form JSON: a value of the wrong type is ignored, it must never fail the whole week.
    String? text(Object? v) {
      final t = v is String ? v.trim() : null;
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
      description: text(extra['description']),
      soldOut: extra['sold_out'] == true,
      origin: text(extra['origin']),
      dietaryLabels: extra['labels_verified'] == true && extra['labels'] is List
          ? [
              for (final l in extra['labels'] as List)
                if (l is String && _knownLabels.contains(l.toUpperCase()))
                  l.toUpperCase(),
            ]
          : const [],
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
