import 'dart:async';

import 'package:meogeobojo/features/auth/models/user_profile.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/repositories/campus_meal_repository.dart';
import 'package:meogeobojo/features/content/models/app_content.dart';
import 'package:meogeobojo/features/contributions/models/contribution.dart';
import 'package:meogeobojo/features/contributions/repositories/contribution_repository.dart';
import 'package:meogeobojo/features/reviews/models/student_review.dart';
import 'package:meogeobojo/features/reviews/repositories/review_repository.dart';
import 'package:meogeobojo/features/content/repositories/app_content_repository.dart';
import 'package:meogeobojo/features/campus_meals/utils/seoul_date.dart';
import 'package:meogeobojo/features/auth/repositories/profile_repository.dart';
import 'package:meogeobojo/features/auth/services/auth_gateway.dart';
import 'package:meogeobojo/features/favorites/repositories/favorites_repository.dart';
import 'package:meogeobojo/features/missions/models/mission_models.dart';
import 'package:meogeobojo/features/missions/repositories/mission_repository.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/preferences/repositories/preferences_repository.dart';
import 'package:meogeobojo/features/restaurants/models/food_category.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant.dart';
import 'package:meogeobojo/features/restaurants/models/restaurant_override.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_override_repository.dart';
import 'package:meogeobojo/features/restaurants/repositories/restaurant_repository.dart';
import 'package:meogeobojo/features/university/models/university.dart';
import 'package:meogeobojo/features/university/repositories/university_repository.dart';

Restaurant fakeRestaurant(
  String id, {
  String name = '테스트식당',
  String category = '음식점 > 한식',
  String group = 'FD6',
  int distance = 100,
}) => Restaurant(
  kakaoId: id,
  name: '$name$id',
  categoryName: category,
  categoryGroupCode: group,
  address: '충남 아산시',
  roadAddress: '충남 아산시 순천향로 1',
  phone: '',
  latitude: 36.77,
  longitude: 126.93,
  distanceMeters: distance,
  placeUrl: 'https://place.map.kakao.com/$id',
);

class FakeUniversityRepository implements UniversityRepository {
  FakeUniversityRepository(this.list);
  final List<University> list;

  @override
  Future<List<University>> fetchAll() async => list;
}

class FakeRestaurantRepository implements RestaurantRepository {
  FakeRestaurantRepository({this.error, this.items = const []});

  final RestaurantException? error;
  final List<Restaurant> items;
  final nearbyCalls = <(String, FoodCategory)>[];

  /// The cuisine sub-filter of each `nearby` call, parallel to [nearbyCalls].
  final cuisineCalls = <GlobalCuisine>[];

  @override
  Future<List<Restaurant>> nearby({
    required University university,
    FoodCategory category = FoodCategory.all,
    GlobalCuisine cuisine = GlobalCuisine.all,
  }) async {
    nearbyCalls.add((university.nameKo, category));
    cuisineCalls.add(cuisine);
    if (error != null) throw error!;
    return items;
  }

  @override
  Future<List<Restaurant>> search({
    required University university,
    required String query,
  }) async {
    if (error != null) throw error!;
    return items;
  }
}

// ---------------------------------------------------------------------------
// Auth / profile / preferences fakes
// ---------------------------------------------------------------------------

User fakeUser({
  String id = 'user-1',
  String? email = 'tester@example.com',
  Map<String, dynamic>? metadata,
  String provider = 'email',
  List<UserIdentity>? identities,
}) => User(
  id: id,
  appMetadata: {'provider': provider},
  userMetadata: metadata,
  aud: 'authenticated',
  email: email,
  createdAt: '2026-11-01T00:00:00Z',
  identities: identities,
);

Session fakeSession(User user) =>
    Session(accessToken: 'test-access', tokenType: 'bearer', user: user);

/// Scriptable stand-in for Supabase Auth. Nothing here touches the network.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.user});

  final _events = StreamController<AuthState>.broadcast();

  User? user;
  Object? signInError;
  Object? signUpError;
  Object? resendError;
  Object? resetError;
  Object? updatePasswordError;

  /// What `signUp` returns. Default: user created, no session (verify email).
  AuthResponse? signUpResponse;
  bool kakaoOpens = true;

  /// Thrown by signInWithKakao (e.g. the system sheet was cancelled).
  Object? kakaoError;

  /// If set, signInWithKakao waits for it (models the iOS auth-session sheet
  /// staying open until the user finishes).
  Completer<void>? kakaoGate;

  final calls = <String>[];

  /// Emits an auth event the way supabase_flutter would.
  void emit(AuthChangeEvent event, [User? u]) {
    if (event == AuthChangeEvent.signedOut) {
      user = null;
    } else if (u != null) {
      user = u;
    }
    _events.add(AuthState(event, u == null ? null : fakeSession(u)));
  }

  void emitError(Object error) => _events.addError(error);

  @override
  Stream<AuthState> get events => _events.stream;

  @override
  User? get currentUser => user;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    calls.add('signInWithPassword');
    if (signInError != null) throw signInError!;
    final u = fakeUser(email: email);
    user = u;
    return AuthResponse(session: fakeSession(u), user: u);
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    calls.add('signUp');
    if (signUpError != null) throw signUpError!;
    return signUpResponse ??
        AuthResponse(
          user: fakeUser(
            email: email,
            identities: [
              UserIdentity(
                id: 'i',
                userId: 'user-1',
                identityData: const {},
                identityId: 'i',
                provider: 'email',
                createdAt: '2026-11-01T00:00:00Z',
                lastSignInAt: '2026-11-01T00:00:00Z',
              ),
            ],
          ),
        );
  }

  @override
  Future<bool> signInWithKakao() async {
    calls.add('signInWithKakao');
    if (kakaoGate != null) await kakaoGate!.future;
    if (kakaoError != null) throw kakaoError!;
    return kakaoOpens;
  }

  @override
  Future<void> resendSignupEmail(String email) async {
    calls.add('resend:$email');
    if (resendError != null) throw resendError!;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('reset:$email');
    if (resetError != null) throw resetError!;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    if (updatePasswordError != null) throw updatePasswordError!;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    emit(AuthChangeEvent.signedOut);
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.onboardingCompleted = false,
    this.nickname,
    // Most tests are about other flows, so accounts default to having chosen
    // their nickname already. Nickname tests pass `false`.
    this.nicknameIsCustom = true,
  });

  bool onboardingCompleted;
  String? nickname;
  bool nicknameIsCustom;
  String? preferredLanguage;
  Object? loadError;

  /// Thrown by the next setNickname() calls, in order.
  final nicknameErrors = <Object>[];
  final nicknameWrites = <String>[];
  int loads = 0;
  String _userId = 'user-1';
  final languageWrites = <String>[];

  /// Stored avatar key (what `profiles.avatar_path` holds).
  String? avatarPath;
  final avatarWrites = <String>[];

  /// Thrown by the next updateAvatar() calls, in order.
  final avatarErrors = <Object>[];

  /// Stored campus (`profiles.selected_university_id`) and every write to it.
  String? selectedUniversityId;
  final universityWrites = <String>[];
  final universityErrors = <Object>[];

  UserProfile _profile() => UserProfile(
    avatarPath: avatarPath,
    selectedUniversityId: selectedUniversityId,
    id: _userId,
    nickname: nickname,
    nicknameIsCustom: nicknameIsCustom,
    onboardingCompleted: onboardingCompleted,
    preferredLanguage: preferredLanguage,
  );

  @override
  Future<UserProfile> loadOrCreate(User user) async {
    loads++;
    _userId = user.id;
    if (loadError != null) throw loadError!;
    return _profile();
  }

  @override
  Future<UserProfile> setNickname(String value) async {
    if (nicknameErrors.isNotEmpty) throw nicknameErrors.removeAt(0);
    nicknameWrites.add(value);
    nickname = value;
    nicknameIsCustom = true;
    return _profile();
  }

  @override
  Future<void> updateLanguage(String userId, String languageCode) async {
    languageWrites.add(languageCode);
  }

  @override
  Future<void> updateAvatar(String userId, String avatarKey) async {
    if (avatarErrors.isNotEmpty) throw avatarErrors.removeAt(0);
    avatarWrites.add(avatarKey);
    avatarPath = avatarKey;
  }

  @override
  Future<void> updateUniversity(String userId, String universityId) async {
    if (universityErrors.isNotEmpty) throw universityErrors.removeAt(0);
    universityWrites.add(universityId);
    selectedUniversityId = universityId;
  }
}

class FakePreferencesRepository implements PreferencesRepository {
  FakePreferencesRepository({this.stored});

  UserPreferences? stored;

  /// Failures to raise on the next save() calls, in order.
  final saveErrors = <Object>[];
  final saved = <UserPreferences>[];
  Completer<void>? gate;

  @override
  Future<UserPreferences?> fetch(String userId) async => stored;

  @override
  Future<UserProfile> save(UserPreferences preferences) async {
    if (gate != null) await gate!.future;
    if (saveErrors.isNotEmpty) throw saveErrors.removeAt(0);
    saved.add(preferences);
    stored = preferences;
    return UserProfile(
      id: 'user-1',
      nicknameIsCustom: true,
      onboardingCompleted: true,
    );
  }
}

class FakeFavoritesRepository implements FavoritesRepository {
  FakeFavoritesRepository([Set<String>? ids]) : ids = {...?ids};

  final Set<String> ids;
  final log = <String>[];

  @override
  Future<Set<String>> fetchIds() async => {...ids};

  @override
  Future<void> add(String kakaoPlaceId) async {
    log.add('add:$kakaoPlaceId');
    ids.add(kakaoPlaceId);
  }

  @override
  Future<void> remove(String kakaoPlaceId) async {
    log.add('remove:$kakaoPlaceId');
    ids.remove(kakaoPlaceId);
  }
}

// ---------------------------------------------------------------------------
// Campus meals
// ---------------------------------------------------------------------------

CampusCafeteria fakeCafeteria(
  String id, {
  String universityId = '5c0a8f3e-0001-4a6e-9b1d-000000000001',
  CafeteriaKind kind = CafeteriaKind.student,
  String? nameKo,
  String? nameEn,
  String? nameZh,
  String? operatingNote,
  List<MealType> mealTypes = MealType.values,
  Set<int> operatingDays = const {1, 2, 3, 4, 5},
  String? photoUrl,
}) => CampusCafeteria(
  id: id,
  universityId: universityId,
  kind: kind,
  nameKo: nameKo,
  nameEn: nameEn,
  nameZh: nameZh,
  operatingNote: operatingNote,
  mealTypes: mealTypes,
  operatingDays: operatingDays,
  photoUrl: photoUrl,
);

CafeteriaMeal fakeMeal(
  String date,
  MealType type, {
  String cafeteriaId = 'c1',
  String option = '',
  int order = 0,
  List<MenuItem> items = const [
    MenuItem(nameKo: '김치찌개', kind: MenuItemKind.main),
  ],
  MealStatus status = MealStatus.published,
  int? price,
  String? start,
  String? end,
  String? source,
  String? badge,
  String? photoUrl,
  String? notice,
  String? description,
  bool soldOut = false,
}) => CafeteriaMeal(
  id: '$cafeteriaId-$date-${type.name}-$option',
  cafeteriaId: cafeteriaId,
  date: parseIsoDate(date),
  type: type,
  optionName: option,
  optionOrder: order,
  items: items,
  status: status,
  priceKrw: price,
  startTime: start,
  endTime: end,
  sourceUrl: source,
  badge: badge,
  photoUrl: photoUrl,
  notice: notice,
  description: description,
  soldOut: soldOut,
  verifiedAt: DateTime.utc(2026, 11, 2, 0),
);

class FakeCampusMealRepository implements CampusMealRepository {
  FakeCampusMealRepository({
    this.cafeteriasByUniversity = const {},
    this.meals = const [],
  });

  Map<String, List<CampusCafeteria>> cafeteriasByUniversity;
  List<CafeteriaMeal> meals;

  /// Failures raised by the next calls, in order.
  final weekErrors = <Object>[];
  final cafeteriaErrors = <Object>[];
  final cafeteriaCalls = <String>[];
  final weekCalls = <(String, String)>[];

  @override
  Future<List<CampusCafeteria>> cafeterias(String universityId) async {
    cafeteriaCalls.add(universityId);
    if (cafeteriaErrors.isNotEmpty) throw cafeteriaErrors.removeAt(0);
    return cafeteriasByUniversity[universityId] ?? const [];
  }

  @override
  Future<List<CafeteriaMeal>> weekMeals({
    required String cafeteriaId,
    required DateTime weekStart,
  }) async {
    weekCalls.add((cafeteriaId, isoDate(weekStart)));
    if (weekErrors.isNotEmpty) throw weekErrors.removeAt(0);
    final end = weekDays(weekStart).last;
    return meals
        .where(
          (m) =>
              m.cafeteriaId == cafeteriaId &&
              !m.date.isBefore(weekStart) &&
              !m.date.isAfter(end),
        )
        .toList();
  }
}

/// Stands in for what the admin dashboard wrote to `restaurant_overrides` /
/// `restaurant_menus`. Mutate [overrides] / [menuItems] to simulate an edit.
class FakeRestaurantOverrideRepository implements RestaurantOverrideRepository {
  FakeRestaurantOverrideRepository({
    Map<String, RestaurantOverride>? overrides,
    Map<String, List<RestaurantMenuItem>>? menuItems,
    Map<String, List<RestaurantPhoto>>? photoItems,
  }) : overrides = overrides ?? {},
       menuItems = menuItems ?? {},
       photoItems = photoItems ?? {};

  Map<String, RestaurantOverride> overrides;
  Map<String, List<RestaurantMenuItem>> menuItems;
  Map<String, List<RestaurantPhoto>> photoItems;

  /// How many times the app asked for overrides (a refresh shows up here).
  int forPlacesCalls = 0;

  @override
  Future<Map<String, RestaurantOverride>> forPlaces(List<String> ids) async {
    forPlacesCalls++;
    return {
      for (final id in ids)
        if (overrides[id] != null) id: overrides[id]!,
    };
  }

  @override
  Future<List<RestaurantMenuItem>> menus(String kakaoId) async =>
      menuItems[kakaoId] ?? const [];

  @override
  Future<List<RestaurantPhoto>> photos(String kakaoId) async =>
      photoItems[kakaoId] ?? const [];
}

/// The server's mission logic lives in SQL (see supabase/tests/missions_test.sql);
/// the app only shows what comes back, so the fake returns whatever the test
/// sets and records how it was called.
class FakeMissionRepository implements MissionRepository {
  FakeMissionRepository({MissionDashboard? dashboard})
    : dashboard = dashboard ?? const MissionDashboard(missions: []);

  MissionDashboard dashboard;
  Object? error;
  int syncs = 0;
  final activity = <(String, String)>[];

  /// Returned (once) by the next logActivity call, like a server completing a mission.
  final completionsOnActivity = <CompletedMission>[];

  @override
  Future<MissionDashboard> sync() async {
    syncs++;
    if (error != null) throw error!;
    return dashboard;
  }

  @override
  Future<List<CompletedMission>> logActivity(
    String event, {
    String ref = '',
  }) async {
    activity.add((event, ref));
    if (error != null) throw error!;
    final out = [...completionsOnActivity];
    completionsOnActivity.clear();
    return out;
  }
}

/// `app_content` rows that are live (the database filters drafts and expired items).
class FakeAppContentRepository implements AppContentRepository {
  FakeAppContentRepository([this.items = const []]);

  List<AppContent> items;
  int loads = 0;

  /// Simulates an outage: the read throws instead of answering.
  bool failing = false;

  @override
  Future<List<AppContent>> live() async {
    loads++;
    if (failing) throw TimeoutException('offline');
    return List.of(items);
  }
}

/// `student_reviews` for a test: rows are what row-level security would return
/// (visible ones + the signed-in user's own), so the test sets them directly.
class FakeReviewRepository implements ReviewRepository {
  FakeReviewRepository([List<StudentReview>? reviews])
    : reviews = reviews ?? [];

  List<StudentReview> reviews;
  Object? saveError;
  final saves =
      <({String kakaoId, int rating, String? body, String? universityId})>[];
  final deletes = <String>[];
  final reports = <({String reviewId, String reason})>[];
  ReportOutcome reportOutcome = ReportOutcome.sent;
  Object? reportError;

  @override
  Future<List<StudentReview>> forPlace(String kakaoId) async => [
    for (final r in reviews)
      if (r.kakaoPlaceId == kakaoId) r,
  ];

  @override
  Future<void> save({
    required String userId,
    required String kakaoId,
    required String? universityId,
    required int rating,
    required String? body,
  }) async {
    if (saveError != null) throw saveError!;
    saves.add((
      kakaoId: kakaoId,
      rating: rating,
      body: body,
      universityId: universityId,
    ));
    reviews = [
      for (final r in reviews)
        if (!(r.userId == userId && r.kakaoPlaceId == kakaoId)) r,
      StudentReview(
        id: 'r-${saves.length}',
        userId: userId,
        kakaoPlaceId: kakaoId,
        rating: rating,
        body: body?.trim().isEmpty ?? true ? null : body!.trim(),
        createdAt: DateTime.utc(2026, 11, 10),
      ),
    ];
  }

  @override
  Future<void> delete(String reviewId) async {
    deletes.add(reviewId);
    reviews = [
      for (final r in reviews)
        if (r.id != reviewId) r,
    ];
  }

  @override
  Future<List<StudentReview>> mine(String userId) async => [
    for (final r in reviews)
      if (r.userId == userId) r,
  ];

  @override
  Future<ReportOutcome> report({
    required String reviewId,
    required String reason,
    String? description,
  }) async {
    if (reportError != null) throw reportError!;
    reports.add((reviewId: reviewId, reason: reason));
    return reportOutcome;
  }
}

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker([this.next]);

  PickedPhoto? next;
  int picks = 0;

  @override
  Future<PickedPhoto?> pick() async {
    picks++;
    return next;
  }
}

class FakeContributionRepository implements ContributionRepository {
  FakeContributionRepository([List<Contribution>? items]) : items = items ?? [];

  List<Contribution> items;
  ContributionException? submitError;
  final submissions =
      <
        ({
          ContributionKind kind,
          String kakaoPlaceId,
          String? caption,
          int bytes,
        })
      >[];
  final withdrawn = <String>[];

  @override
  Future<void> submitPhoto({
    required String userId,
    required ContributionKind kind,
    required String kakaoPlaceId,
    required PickedPhoto photo,
    String? caption,
  }) async {
    if (submitError != null) throw submitError!;
    submissions.add((
      kind: kind,
      kakaoPlaceId: kakaoPlaceId,
      caption: caption?.trim(),
      bytes: photo.bytes.length,
    ));
    items = [
      Contribution(
        id: 'c-${submissions.length}',
        kind: kind,
        kakaoPlaceId: kakaoPlaceId,
        status: 'pending',
        createdAt: DateTime.utc(2026, 11, 10),
        caption: caption?.trim().isEmpty ?? true ? null : caption!.trim(),
        path: '$userId/x.jpg',
      ),
      ...items,
    ];
  }

  @override
  Future<List<Contribution>> mine(String userId) async => items;

  @override
  Future<void> withdraw(Contribution c) async {
    withdrawn.add(c.id);
    items = [
      for (final i in items)
        if (i.id != c.id) i,
    ];
  }
}
