import '../features/university/models/verified_universities.dart';

enum CampusPointKind { gate, college, building }

/// A named spot on a campus that can be picked as the walking origin.
class CampusPoint {
  const CampusPoint(
    this.id,
    this.kind,
    this.name,
    this.latitude,
    this.longitude,
  );

  final String id;
  final CampusPointKind kind;

  /// Proper name, shown as-is in every language.
  final String name;
  final double latitude;
  final double longitude;
}

/// Id of the point used for "학생회관에서 도보 15분 안" on the cafeteria card.
const kStudentCenterPointId = 'student_center';

/// DEMO POSITIONS. These are NOT surveyed: they are spread a few hundred
/// metres around the campus landmark stored in `kVerifiedUniversities`, which
/// is enough to show origin-dependent distances in the demo. Replace the
/// lat/lng values here with real coordinates; nothing else needs to change.
const kCampusPointsByUniversity = <String, List<CampusPoint>>{
  kDefaultUniversityId: [
    // gates
    CampusPoint('gate_front', CampusPointKind.gate, '정문', 36.76800, 126.93050),
    CampusPoint('gate_back', CampusPointKind.gate, '후문', 36.77200, 126.93350),
    // colleges
    CampusPoint(
      'col_eng',
      CampusPointKind.college,
      '공과대학',
      36.77050,
      126.93000,
    ),
    CampusPoint(
      'col_sw',
      CampusPointKind.college,
      'SW융합대학',
      36.77100,
      126.93200,
    ),
    CampusPoint(
      'col_hss',
      CampusPointKind.college,
      '인문사회과학대학',
      36.76900,
      126.93100,
    ),
    CampusPoint(
      'col_biz',
      CampusPointKind.college,
      '글로벌경영대학',
      36.76850,
      126.93250,
    ),
    CampusPoint(
      'col_med',
      CampusPointKind.college,
      '의료과학대학',
      36.77150,
      126.93100,
    ),
    CampusPoint(
      'col_sci',
      CampusPointKind.college,
      '자연과학대학',
      36.77180,
      126.93280,
    ),
    // major buildings
    CampusPoint(
      'b_library',
      CampusPointKind.building,
      '중앙도서관',
      36.76999,
      126.93150,
    ),
    CampusPoint(
      kStudentCenterPointId,
      CampusPointKind.building,
      '학생회관',
      36.76950,
      126.93180,
    ),
    CampusPoint('b_dorm', CampusPointKind.building, '기숙사', 36.77250, 126.93200),
  ],
};

List<CampusPoint> campusPointsFor(String universityId) =>
    kCampusPointsByUniversity[universityId] ?? const [];
