import '../features/university/models/verified_universities.dart';

enum CampusPointKind { gate, dorm, building }

/// A named spot on a campus that can be picked as the walking origin.
class CampusPoint {
  const CampusPoint(
    this.id,
    this.kind,
    this.name,
    this.latitude,
    this.longitude, {
    required this.source,
    required this.checkedOn,
    this.entrance = false,
  });

  final String id;
  final CampusPointKind kind;

  /// Proper name, shown as-is in every language.
  final String name;
  final double latitude;
  final double longitude;

  /// Where the coordinate comes from (an OpenStreetMap element, ...).
  final String source;

  /// When the coordinate was checked against [source] (YYYY-MM-DD).
  final String checkedOn;

  /// True only when the coordinate is the walkers' way in (a gate, an
  /// entrance surveyed on site). False: the centre of the building outline,
  /// to be replaced by the pedestrian entrance once someone checks it.
  final bool entrance;
}

/// Id of the point used for "학생회관에서 도보 15분 안" on the cafeteria card.
const kStudentCenterPointId = 'student_center';

/// The single "기숙사" point older versions offered. Users who saved it must
/// pick their own residence hall again (it is never mapped to one of them).
const kLegacyDormPointId = 'b_dorm';

const _osmChecked = '2026-11-12';

/// Campus origins, checked against OpenStreetMap (data as of 2026-07-15,
/// © OpenStreetMap contributors, ODbL) on [_osmChecked].
///
/// Only 후문 is a mapped gate. 정문 has no gate in OSM: its point is where
/// the campus access road (way 1253843202) meets the public road, an
/// estimate. Buildings are the centre of their OSM outline, NOT the
/// pedestrian entrance. Replace a point with the surveyed entrance and set
/// `entrance: true`; nothing else needs to change.
const kCampusPointsByUniversity = <String, List<CampusPoint>>{
  kDefaultUniversityId: [
    // 정문·후문
    CampusPoint(
      'gate_front',
      CampusPointKind.gate,
      '정문',
      36.769563,
      126.927360,
      source: 'OSM way 1253843202 (캠퍼스 진입로 끝점, 추정)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'gate_back',
      CampusPointKind.gate,
      '후문',
      36.7732247,
      126.9335642,
      source: 'OSM node 4690493598 (순천향대학교후문)',
      checkedOn: _osmChecked,
      entrance: true,
    ),
    // 기숙사
    CampusPoint(
      'dorm_hyangseol_1',
      CampusPointKind.dorm,
      '향설생활관 1관',
      36.7685811,
      126.9322936,
      source: 'OSM way 601092164 (향설생활관1)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'dorm_hyangseol_2',
      CampusPointKind.dorm,
      '향설생활관 2관',
      36.7679277,
      126.9335413,
      source: 'OSM way 471699802 (향설생활관2)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'dorm_hyangseol_3',
      CampusPointKind.dorm,
      '향설생활관 3관',
      36.7679578,
      126.9347341,
      source: 'OSM way 471699804 (향설생활관3)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'dorm_global_village',
      CampusPointKind.dorm,
      '글로벌 빌리지',
      36.7672622,
      126.9338298,
      source: 'OSM way 601094043 (글로벌빌리지)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'dorm_hakseong_1',
      CampusPointKind.dorm,
      '학성사 1관',
      36.7723622,
      126.9334757,
      source: 'OSM way 471699822 (학성사1)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'dorm_hakseong_2',
      CampusPointKind.dorm,
      '학성사 2관',
      36.7719432,
      126.9337094,
      source: 'OSM way 471699821 (학성사2)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'dorm_hakseong_3',
      CampusPointKind.dorm,
      '학성사 3관',
      36.7714102,
      126.9341687,
      source: 'OSM way 471699820 (학성사3)',
      checkedOn: _osmChecked,
    ),
    // 주요 건물
    CampusPoint(
      'col_eng',
      CampusPointKind.building,
      '공과대학',
      36.7692366,
      126.9321798,
      source: 'OSM way 471699794 (공과대학)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'col_sci',
      CampusPointKind.building,
      '자연과학대학',
      36.7696186,
      126.9301492,
      source: 'OSM way 471699798 (자연과학대학)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'col_med',
      CampusPointKind.building,
      '의료과학대학',
      36.7711885,
      126.9320862,
      source: 'OSM way 471699811 (의료과학대)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'col_hss',
      CampusPointKind.building,
      '인문과학대학',
      36.7683628,
      126.9275085,
      source: 'OSM way 471699815 (인문과학대학)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      'b_library',
      CampusPointKind.building,
      '중앙도서관',
      36.7687285,
      126.9307218,
      source: 'OSM node 368657618 (순천향대학교중앙도서관)',
      checkedOn: _osmChecked,
    ),
    CampusPoint(
      kStudentCenterPointId,
      CampusPointKind.building,
      '학생회관',
      36.7699952,
      126.9314545,
      source: 'OSM way 471699799 (학생회관)',
      checkedOn: _osmChecked,
    ),
  ],
};

List<CampusPoint> campusPointsFor(String universityId) =>
    kCampusPointsByUniversity[universityId] ?? const [];
