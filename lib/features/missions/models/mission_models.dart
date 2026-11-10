import 'package:flutter/material.dart';

/// Mission text is written by admins and may contain emoji (e.g. 🍁). The
/// app's text font has no emoji glyphs and not every device falls back to an
/// emoji font, so they would show as "?" boxes; they are dropped here.
final _emoji = RegExp(
  '[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{2460}-\u{24FF}'
  '\u{25A0}-\u{27BF}\u{2900}-\u{2BFF}\u{FE0E}\u{FE0F}\u{200D}\u{20E3}]',
  unicode: true,
);

String? cleanMissionText(Object? v) {
  if (v is! String) return null;
  return v.replaceAll(_emoji, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

enum MissionKind {
  monthly,
  daily,
  weekly,
  achievement;

  static MissionKind fromDb(Object? v) => values.firstWhere(
    (k) => k.name == v,
    orElse: () => MissionKind.achievement,
  );
}

/// What the app shows for one mission right now.
enum MissionState {
  active,
  completed,

  /// The window has ended without completion.
  expired,

  /// The window has not started yet.
  upcoming;

  static MissionState fromDb(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => MissionState.active);
}

/// Where a mission's action button leads. A closed list: the database cannot
/// send the app somewhere it does not know.
enum MissionAction {
  none,
  recommend,
  map,
  favorites,
  review,
  photo,
  correct,
  categories;

  static MissionAction fromDb(Object? v) =>
      values.firstWhere((a) => a.name == v, orElse: () => MissionAction.none);
}

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

/// A campaign's own `#RRGGBB` theme colour; null when absent or malformed
/// (the banner then uses the app's accent).
Color? _color(Object? v) {
  if (v is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) {
    final n = int.parse(v.substring(1), radix: 16);
    return Color.fromARGB(255, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF);
  }
  return null;
}

/// Korea has no daylight saving: Seoul is always UTC+9.
DateTime toSeoul(DateTime utc) => utc.toUtc().add(const Duration(hours: 9));

/// "2026.11.01" in Seoul time.
String formatSeoulDate(DateTime utc) {
  final d = toSeoul(utc);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)}';
}

@immutable
class MissionCampaign {
  const MissionCampaign({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.subtitle,
    this.themeColor,
    this.bannerMascot = 'cheer',
    this.state = 'active',
  });

  final String id;
  final String title;
  final String? subtitle;
  final Color? themeColor;
  final String bannerMascot;

  /// UTC. [endsAt] is exclusive (November ends at 12-01 00:00 Seoul).
  final DateTime startsAt;
  final DateTime endsAt;
  final String state;

  /// "2026.11.01 – 2026.11.30": the last day is the day before [endsAt].
  String get periodLabel =>
      '${formatSeoulDate(startsAt)} – ${formatSeoulDate(endsAt.subtract(const Duration(seconds: 1)))}';

  bool get isEnded => state == 'ended';

  factory MissionCampaign.fromJson(Map<String, dynamic> j) => MissionCampaign(
    id: j['id'] as String,
    title: cleanMissionText(j['title']) ?? '',
    subtitle: cleanMissionText(j['subtitle']),
    themeColor: _color(j['theme_color']),
    bannerMascot: j['banner_mascot'] as String? ?? 'cheer',
    startsAt:
        _date(j['starts_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    endsAt:
        _date(j['ends_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    state: j['state'] as String? ?? 'active',
  );
}

@immutable
class Mission {
  const Mission({
    required this.id,
    required this.title,
    required this.kind,
    required this.rewardPoints,
    required this.target,
    required this.progress,
    required this.state,
    this.slug = '',
    this.description,
    this.icon = 'star',
    this.ruleType = '',
    this.action = MissionAction.none,
    this.sortOrder = 0,
    this.endsAt,
    this.badgeKey,
    this.badgeName,
    this.badgeMascot,
    this.recurrence = 'none',
  });

  final String id;
  final String slug;
  final MissionKind kind;
  final String title;
  final String? description;
  final String icon;
  final int rewardPoints;
  final String ruleType;
  final int target;
  final int progress;
  final MissionState state;
  final MissionAction action;
  final int sortOrder;
  final DateTime? endsAt;
  final String? badgeKey;
  final String? badgeName;
  final String? badgeMascot;
  final String recurrence;

  bool get completed => state == MissionState.completed;

  /// The campaign's final mission: pays a badge, not points.
  bool get isMaster => ruleType == 'missions_completed';

  double get fraction =>
      target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0).toDouble();

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
    id: j['id'] as String,
    slug: j['slug'] as String? ?? '',
    kind: MissionKind.fromDb(j['kind']),
    title: cleanMissionText(j['title']) ?? '',
    description: cleanMissionText(j['description']),
    icon: j['icon'] as String? ?? 'star',
    rewardPoints: (j['reward_points'] as num?)?.toInt() ?? 0,
    ruleType: j['rule_type'] as String? ?? '',
    target: (j['target'] as num?)?.toInt() ?? 1,
    progress: (j['progress'] as num?)?.toInt() ?? 0,
    state: MissionState.fromDb(j['state']),
    action: MissionAction.fromDb(j['action_key']),
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    endsAt: _date(j['ends_at']),
    badgeKey: j['badge_key'] as String?,
    badgeName: j['badge_name'] as String?,
    badgeMascot: j['badge_mascot'] as String?,
    recurrence: j['recurrence'] as String? ?? 'none',
  );
}

@immutable
class MissionBadge {
  const MissionBadge({required this.key, required this.name, this.mascot});

  final String key;
  final String name;
  final String? mascot;

  factory MissionBadge.fromJson(Map<String, dynamic> j) => MissionBadge(
    key: j['badge_key'] as String? ?? '',
    name: cleanMissionText(j['name']) ?? '',
    mascot: j['mascot'] as String?,
  );
}

/// A mission this call just completed (for the celebration, shown once).
@immutable
class CompletedMission {
  const CompletedMission({
    required this.title,
    required this.points,
    this.badgeKey,
  });

  final String title;
  final int points;
  final String? badgeKey;

  factory CompletedMission.fromJson(Map<String, dynamic> j) => CompletedMission(
    title: cleanMissionText(j['title']) ?? '',
    points: (j['points'] as num?)?.toInt() ?? 0,
    badgeKey: j['badge_key'] as String?,
  );
}

@immutable
class MissionDashboard {
  const MissionDashboard({
    required this.missions,
    this.campaign,
    this.pointsTotal = 0,
    this.pointsCampaign = 0,
    this.badges = const [],
    this.newlyCompleted = const [],
  });

  final MissionCampaign? campaign;
  final List<Mission> missions;
  final int pointsTotal;
  final int pointsCampaign;
  final List<MissionBadge> badges;
  final List<CompletedMission> newlyCompleted;

  List<Mission> byKind(MissionKind k) => [
    for (final m in missions)
      if (m.kind == k) m,
  ];

  /// The campaign's regular missions (everything but the final one).
  List<Mission> get mainMonthly => [
    for (final m in byKind(MissionKind.monthly))
      if (!m.isMaster) m,
  ];

  Mission? get master {
    for (final m in byKind(MissionKind.monthly)) {
      if (m.isMaster) return m;
    }
    return null;
  }

  int get completedMain => mainMonthly.where((m) => m.completed).length;
  int get totalMain => mainMonthly.length;

  double get monthlyFraction => totalMain == 0 ? 0 : completedMain / totalMain;

  bool hasBadge(String? key) => badges.any((b) => b.key == key);

  factory MissionDashboard.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(Object? v, T Function(Map<String, dynamic>) f) => [
      for (final e in (v as List? ?? const []))
        if (e is Map<String, dynamic>) f(e),
    ];
    final campaign = j['campaign'];
    return MissionDashboard(
      campaign: campaign is Map<String, dynamic>
          ? MissionCampaign.fromJson(campaign)
          : null,
      missions: list(j['missions'], Mission.fromJson),
      pointsTotal: (j['points_total'] as num?)?.toInt() ?? 0,
      pointsCampaign: (j['points_campaign'] as num?)?.toInt() ?? 0,
      badges: list(j['badges'], MissionBadge.fromJson),
      newlyCompleted: list(j['newly_completed'], CompletedMission.fromJson),
    );
  }
}
