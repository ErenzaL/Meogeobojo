import 'university.dart';

/// Offline copy of the rows seeded by
/// `supabase/migrations/20261031000100_universities.sql` (same ids).
///
/// Used only when the `universities` table is unreachable or not yet
/// migrated, so the app stays usable. Coordinates are Kakao Map landmark
/// points inside each campus (see the migration for the landmark used).
const kDefaultUniversityId = '5c0a8f3e-0001-4a6e-9b1d-000000000001';

/// Whether the app has data for [u]. Only 순천향대학교 does for now: the other
/// schools are listed as "준비 중" and can never become the selected campus
/// (their name over 순천향대 data would be wrong).
bool isSupportedUniversity(University u) =>
    u.id == kDefaultUniversityId || u.nameKo == '순천향대학교';

const kVerifiedUniversities = <University>[
  University(
    id: kDefaultUniversityId,
    nameKo: '순천향대학교',
    nameEn: 'Soonchunhyang University',
    city: '아산',
    latitude: 36.76999,
    longitude: 126.93150,
  ),
  University(
    id: '5c0a8f3e-0002-4a6e-9b1d-000000000002',
    nameKo: '호서대학교',
    nameEn: 'Hoseo University',
    city: '아산',
    latitude: 36.73959,
    longitude: 127.07422,
  ),
  University(
    id: '5c0a8f3e-0003-4a6e-9b1d-000000000003',
    nameKo: '선문대학교',
    nameEn: 'Sun Moon University',
    city: '아산',
    latitude: 36.80023,
    longitude: 127.07493,
  ),
  University(
    id: '5c0a8f3e-0004-4a6e-9b1d-000000000004',
    nameKo: '단국대학교 천안캠퍼스',
    nameEn: 'Dankook University (Cheonan)',
    city: '천안',
    latitude: 36.83849,
    longitude: 127.17021,
  ),
  University(
    id: '5c0a8f3e-0005-4a6e-9b1d-000000000005',
    nameKo: '백석대학교',
    nameEn: 'Baekseok University',
    city: '천안',
    latitude: 36.83943,
    longitude: 127.18354,
  ),
  University(
    id: '5c0a8f3e-0006-4a6e-9b1d-000000000006',
    nameKo: '상명대학교 천안캠퍼스',
    nameEn: 'Sangmyung University (Cheonan)',
    city: '천안',
    latitude: 36.83250,
    longitude: 127.17879,
  ),
  University(
    id: '5c0a8f3e-0007-4a6e-9b1d-000000000007',
    nameKo: '한국기술교육대학교',
    nameEn: 'Korea University of Technology and Education',
    city: '천안',
    latitude: 36.76303,
    longitude: 127.28127,
  ),
];
