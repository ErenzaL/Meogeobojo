// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonCancel => '취소';

  @override
  String get commonClose => '닫기';

  @override
  String get commonLater => '나중에';

  @override
  String get commonSave => '저장';

  @override
  String get tryAgainLater => '잠시 후 다시 시도해주세요.';

  @override
  String get mascotSemantics => '먹어보조 마스코트';

  @override
  String get errPermissionDenied => '이 작업을 할 권한이 없어요. 다시 로그인한 뒤 시도해주세요.';

  @override
  String get navHome => '홈';

  @override
  String get navCommunity => '밥수다';

  @override
  String get navMap => '지도';

  @override
  String get navRecords => '기록';

  @override
  String get navProfile => 'MY';

  @override
  String get languageSheetTitle => '언어 설정';

  @override
  String get languageButtonTooltip => '언어 설정';

  @override
  String get profileLanguage => '언어 설정';

  @override
  String homeHeroAround(String university) {
    return '$university 주변에서';
  }

  @override
  String get homeHeroTitle => '오늘 뭐 먹을지\n찾아볼까요?';

  @override
  String get homeHeroSubtitle => '맛있는 한 끼가 기다리고 있어요!';

  @override
  String get homeSearchLabel => '검색';

  @override
  String get searchHint => '메뉴, 식당, 키워드로 검색해보세요';

  @override
  String get homeNotificationsLabel => '알림';

  @override
  String get homeNotificationsSoon => '알림 기능은 준비 중이에요.';

  @override
  String get homeMore => '더보기 >';

  @override
  String get homeNearbyTitle => '학교 주변 맛집';

  @override
  String get homeMenuTitle => '메뉴별로 찾아보기';

  @override
  String get homeBannerLabel => '오늘의 한 끼 추천';

  @override
  String get homeBannerTitle => '오늘은 이거 어때요?';

  @override
  String get homeBannerSubtitle => '지금 인기 있는 맛집을 확인해보세요!';

  @override
  String get homeBannerCta => '추천 보러가기';

  @override
  String get categoryAll => '전체';

  @override
  String get categoryKorean => '한식';

  @override
  String get categoryWestern => '양식';

  @override
  String get categoryChinese => '중식';

  @override
  String get categoryJapanese => '일식';

  @override
  String get categoryCafeDessert => '카페·디저트';

  @override
  String get categorySnack => '분식';

  @override
  String get categoryEtc => '기타';

  @override
  String get menuMalatang => '마라탕';

  @override
  String get menuPorkCutlet => '돈까스';

  @override
  String get menuNaengmyeon => '냉면';

  @override
  String get menuSoondubu => '순두부찌개';

  @override
  String get menuChicken => '치킨';

  @override
  String get menuTteokbokki => '떡볶이';

  @override
  String get menuPasta => '파스타';

  @override
  String get menuAmericano => '아메리카노';

  @override
  String get restaurantLoadFailedTitle => '맛집을 불러오지 못했어요';

  @override
  String get restaurantLoadFailedMessage => '맛집 정보를 불러오지 못했어요.';

  @override
  String get restaurantEmptyTitle => '아직 주변 맛집을 찾지 못했어요';

  @override
  String get universityChange => '학교 바꾸기';

  @override
  String restaurantListSubtitle(String university, String category) {
    return '$university · $category · 가까운 순';
  }

  @override
  String restaurantTagDistance(String tag, String distance) {
    return '$tag · 학교에서 $distance';
  }

  @override
  String restaurantDistanceFromSchool(String distance) {
    return '학교에서 $distance';
  }

  @override
  String restaurantDistanceStraight(String distance) {
    return '학교에서 $distance (직선거리)';
  }

  @override
  String get restaurantNoAddress => '주소 정보가 없어요';

  @override
  String get restaurantNoPhone => '등록된 전화번호가 없어요';

  @override
  String get restaurantDataNotice =>
      '사진, 평점, 메뉴·가격, 영업시간은 아직 제공되지 않아요. 자세한 정보는 카카오맵에서 확인해보세요.';

  @override
  String get restaurantOpenKakaoMap => '카카오맵에서 보기';

  @override
  String get restaurantLinkOpenFailed => '열 수 없는 링크예요.';

  @override
  String get restaurantErrNetwork => '인터넷 연결을 확인해주세요.';

  @override
  String get restaurantErrTimeout => '응답이 너무 늦어지고 있어요. 잠시 후 다시 시도해주세요.';

  @override
  String get restaurantErrQuota => '요청이 많아 잠시 후 다시 시도해주세요.';

  @override
  String get restaurantErrAuth => '맛집 검색 서버 인증에 실패했어요.';

  @override
  String get restaurantErrInvalid => '검색 조건이 올바르지 않아요.';

  @override
  String get restaurantErrUpstream => '맛집 정보를 가져오는 중 서버에 문제가 생겼어요.';

  @override
  String get restaurantErrUnknown => '알 수 없는 오류가 발생했어요.';

  @override
  String get searchIdleTitle => '무엇을 먹고 싶으세요?';

  @override
  String searchIdleMessage(String university) {
    return '$university 주변에서 찾아드릴게요.';
  }

  @override
  String searchNoResultsTitle(String query) {
    return '\'$query\' 검색 결과가 없어요';
  }

  @override
  String get searchNoResultsMessage => '다른 키워드로 검색하거나 학교를 바꿔보세요.';

  @override
  String searchResultsSummary(String university, int count) {
    return '$university 주변 · 가까운 순 $count곳';
  }

  @override
  String mapStatusLoading(String university) {
    return '$university · 맛집 불러오는 중…';
  }

  @override
  String mapStatusError(String university) {
    return '$university · 맛집을 불러오지 못했어요';
  }

  @override
  String mapStatusCount(String university, int count) {
    return '$university · 주변 $count곳';
  }

  @override
  String get mapErrorTitle => '지도를 불러오지 못했어요';

  @override
  String get mapErrorMessage => '잠시 후 다시 시도해주세요. 맛집 목록과 검색은 계속 사용할 수 있어요.';

  @override
  String get universitySelect => '학교 선택';

  @override
  String universitySelectCurrent(String name) {
    return '학교 선택, 현재 $name';
  }

  @override
  String get universitySearchHint => '학교 이름 검색';

  @override
  String get universityLoadFailed => '학교 목록을 불러오지 못했어요';

  @override
  String get universityNoMatch => '일치하는 학교가 없어요';

  @override
  String get universityFallbackName => '학교';

  @override
  String get cityAsan => '아산';

  @override
  String get cityCheonan => '천안';

  @override
  String get favoriteAdd => '즐겨찾기 추가';

  @override
  String get favoriteRemove => '즐겨찾기 해제';

  @override
  String get favoriteSaveFailed => '즐겨찾기를 저장하지 못했어요. 잠시 후 다시 시도해주세요.';

  @override
  String get recordsEmptyTitle => '아직 기록이 없어요';

  @override
  String get recordsEmptyMessage => '먹은 음식을 기록하는 기능은 준비 중이에요.';

  @override
  String get communityTitle => '밥수다는 준비 중이에요';

  @override
  String get communityMessage => '같은 학교 친구들과 맛집 이야기를 나눌 수 있도록\n열심히 만들고 있어요!';

  @override
  String recommendStrategyProximity(String university) {
    return '$university에서 가까운 순';
  }

  @override
  String get recommendExplainBaseline =>
      '아직 인기·취향 데이터가 없어서 학교에서 가까운 음식점부터 보여드려요. 맞춤 추천은 준비 중이에요.';

  @override
  String get recommendStrategyPreferences => '내 조건으로 거른 결과';

  @override
  String recommendExplainPreferences(int count, int total) {
    return '저장한 거리·음식 종류 조건을 적용해 $total곳 중 $count곳을 가까운 순으로 보여드려요. 예산·함께 먹는 사람·취향 태그는 아직 반영되지 않고, 거리는 직선거리 기준 근사치예요. 맞춤 추천은 준비 중이에요.';
  }

  @override
  String get recommendNoMatchTitle => '조건에 맞는 맛집이 없어요';

  @override
  String get recommendNoMatchMessage => '거리나 음식 종류 조건을 바꿔보세요.';

  @override
  String get profileGuestTitle => '로그인하고 맛집을 저장해보세요';

  @override
  String get profileGuestSubtitle => '둘러보기와 검색은 로그인 없이도 가능해요.';

  @override
  String get profileLoginButton => '로그인 / 회원가입';

  @override
  String profileGreeting(String nickname) {
    return '안녕하세요, $nickname님';
  }

  @override
  String get profileGreetingSub => '오늘도 맛있는 한 끼 찾아볼까요?';

  @override
  String get profileEditProfile => '프로필 수정 →';

  @override
  String profileCampusHint(String city) {
    return '$city · 탭해서 학교 바꾸기';
  }

  @override
  String get profileCampusHintNoCity => '탭해서 학교 바꾸기';

  @override
  String get profileStatSaved => '저장한 맛집';

  @override
  String get profileStatRecords => '나의 기록';

  @override
  String get profileStatPlans => '예정된 약속';

  @override
  String get profileStatUnavailable => '준비 중';

  @override
  String get profileSaved => '저장한 맛집';

  @override
  String profileSavedCount(int count) {
    return '$count곳';
  }

  @override
  String get profileRecords => '나의 기록';

  @override
  String get profilePreferences => '나의 취향 설정';

  @override
  String get profileAccount => '계정 설정';

  @override
  String get profileLogout => '로그아웃';

  @override
  String get profileDefaultNickname => '먹어보조 사용자';

  @override
  String get savedLoadFailed => '저장한 맛집을 불러오지 못했어요';

  @override
  String get savedEmptyTitle => '아직 저장한 맛집이 없어요';

  @override
  String get savedEmptyMessage => '마음에 드는 식당의 하트를 눌러 저장해보세요.';

  @override
  String savedCount(int count) {
    return '저장한 맛집 $count곳';
  }

  @override
  String savedHiddenNote(int count) {
    return '$count곳은 지금 선택한 학교 주변 목록에 없어 자세한 정보를 보여드릴 수 없어요. 해당 학교를 선택하면 볼 수 있어요.';
  }

  @override
  String get accountNickname => '닉네임';

  @override
  String get accountNicknameEdit => '닉네임 변경';

  @override
  String get accountEmail => '이메일';

  @override
  String get accountLoginMethod => '로그인 방식';

  @override
  String get accountProviderKakao => '카카오';

  @override
  String get accountProviderEmail => '이메일';

  @override
  String get authWelcomeTitle => '먹어보조에 오신 걸 환영해요!';

  @override
  String get authWelcomeSubtitle => '로그인하고 나만의 맛집을 찾아보세요.';

  @override
  String get authContinueKakao => '카카오로 계속하기';

  @override
  String get authEmailLogin => '이메일로 로그인';

  @override
  String get authEmailSignUp => '이메일로 회원가입';

  @override
  String get authBrowseAsGuest => '로그인 없이 계속 둘러보기 →';

  @override
  String get authKakaoWaiting => '카카오 로그인 진행 중…';

  @override
  String get legalTerms => '이용약관';

  @override
  String get legalPrivacy => '개인정보처리방침';

  @override
  String get legalNotPublished => '문서가 아직 게시되지 않았어요.';

  @override
  String get legalOpenFailed => '링크를 열 수 없어요.';

  @override
  String get authEmailLoginTitle => '이메일로 로그인';

  @override
  String get authEmailLabel => '이메일';

  @override
  String get authPasswordLabel => '비밀번호';

  @override
  String get authPasswordConfirmLabel => '비밀번호 확인';

  @override
  String get authNewPasswordLabel => '새 비밀번호';

  @override
  String get authPasswordShow => '비밀번호 보기';

  @override
  String get authPasswordHide => '비밀번호 숨기기';

  @override
  String get authLoginButton => '로그인';

  @override
  String get authForgotPasswordLink => '비밀번호를 잊으셨나요?';

  @override
  String get authNoAccountSignUp => '아직 계정이 없나요? 회원가입';

  @override
  String get authHaveAccountLogin => '이미 계정이 있어요. 로그인';

  @override
  String get authSignUpTitle => '이메일로 회원가입';

  @override
  String get authSignUpSubtitle => '이메일과 비밀번호로 계정을 만들어요. 가입 후 이메일 인증이 필요해요.';

  @override
  String get authSignUpButton => '가입하기';

  @override
  String authPasswordRule(int min) {
    return '$min자 이상 입력해주세요.';
  }

  @override
  String get authVerifyTitle => '이메일을 확인해주세요';

  @override
  String authVerifyMessage(String email) {
    return '$email(으)로 인증 메일을 보냈어요. 메일의 링크를 누르면 가입이 완료돼요.';
  }

  @override
  String get authVerifyNotSignedIn => '인증을 마치기 전까지는 로그인되지 않아요.';

  @override
  String get authVerifyResend => '인증 메일 다시 받기';

  @override
  String authVerifyResendIn(int seconds) {
    return '$seconds초 뒤에 다시 보낼 수 있어요';
  }

  @override
  String get authVerifyResent => '인증 메일을 다시 보냈어요.';

  @override
  String get authVerifyBackToLogin => '로그인으로 돌아가기';

  @override
  String get authForgotTitle => '비밀번호 찾기';

  @override
  String get authForgotMessage => '가입한 이메일을 입력하면 비밀번호 재설정 링크를 보내드려요.';

  @override
  String get authForgotSend => '재설정 메일 보내기';

  @override
  String get authForgotResend => '다시 보내기';

  @override
  String authForgotSent(String email) {
    return '가입된 이메일이라면 $email(으)로 재설정 링크를 보냈어요. 메일함을 확인해주세요.';
  }

  @override
  String get authResetTitle => '새 비밀번호 설정';

  @override
  String get authResetMessage => '새로 사용할 비밀번호를 입력해주세요.';

  @override
  String get authResetButton => '비밀번호 변경하기';

  @override
  String get authResetSuccess => '비밀번호를 변경했어요.';

  @override
  String get errEmailRequired => '이메일을 입력해주세요.';

  @override
  String get errEmailInvalid => '올바른 이메일 형식이 아니에요.';

  @override
  String get errPasswordRequired => '비밀번호를 입력해주세요.';

  @override
  String errPasswordShort(int min) {
    return '비밀번호는 $min자 이상이어야 해요.';
  }

  @override
  String get errPasswordMismatch => '비밀번호가 서로 달라요.';

  @override
  String get authErrInvalidCredentials => '이메일 또는 비밀번호가 올바르지 않아요.';

  @override
  String get authErrEmailNotConfirmed =>
      '이메일 인증이 아직 완료되지 않았어요. 메일의 링크를 눌러 인증해주세요.';

  @override
  String get authErrEmailTaken => '이미 가입된 이메일이에요. 로그인해주세요.';

  @override
  String get authErrInvalidEmail => '올바른 이메일 형식이 아니에요.';

  @override
  String get authErrWeakPassword => '비밀번호가 너무 약해요. 더 길고 복잡하게 만들어주세요.';

  @override
  String get authErrSamePassword => '이전과 다른 비밀번호를 사용해주세요.';

  @override
  String get authErrKakaoCancelled => '카카오 로그인을 취소했어요.';

  @override
  String get authErrKakaoConfig =>
      '카카오 로그인 설정에 문제가 있어요. 잠시 후 다시 시도하고, 계속되면 문의해주세요.';

  @override
  String get authErrDeepLinkMissing =>
      '로그인이 완료되지 않았어요. 취소했거나 앱으로 돌아오지 못했을 수 있어요. 다시 시도해주세요.';

  @override
  String get authErrSessionExpired => '로그인이 만료됐어요. 다시 로그인해주세요.';

  @override
  String get authErrLinkExpired => '링크가 만료됐거나 이미 사용됐어요. 새 링크를 요청해주세요.';

  @override
  String get authErrRateLimited => '요청이 너무 많아요. 잠시 후 다시 시도해주세요.';

  @override
  String get authErrNetwork => '인터넷 연결을 확인하고 다시 시도해주세요.';

  @override
  String get authErrTimeout => '응답이 너무 늦어요. 잠시 후 다시 시도해주세요.';

  @override
  String get authErrPasswordReset => '비밀번호 재설정에 실패했어요. 다시 시도해주세요.';

  @override
  String get authErrProfileLoad => '내 정보를 불러오지 못했어요. 다시 시도해주세요.';

  @override
  String get authErrUnknown => '문제가 생겼어요. 잠시 후 다시 시도해주세요.';

  @override
  String get nicknameSetupTitle => '어떻게 불러드릴까요?';

  @override
  String get nicknameSetupSubtitle => '먹어보조에서 사용할 닉네임을 정해주세요.';

  @override
  String get nicknameLabel => '닉네임';

  @override
  String get nicknameHint => '닉네임을 입력해주세요';

  @override
  String get nicknameNext => '다음';

  @override
  String nicknameRule(int min, int max) {
    return '$min~$max자로 입력해주세요.';
  }

  @override
  String get nicknameErrEmpty => '닉네임을 입력해주세요.';

  @override
  String nicknameErrTooShort(int min) {
    return '닉네임은 $min자 이상이어야 해요.';
  }

  @override
  String nicknameErrTooLong(int max) {
    return '닉네임은 $max자 이하여야 해요.';
  }

  @override
  String get nicknameErrInvalidChars => '사용할 수 없는 문자가 포함되어 있어요.';

  @override
  String get nicknameSaveFailed => '닉네임을 저장하지 못했어요. 다시 시도해주세요.';

  @override
  String get nicknameUpdated => '닉네임을 변경했어요.';

  @override
  String get homeCampusMeals => '학식';

  @override
  String get mealPageTitle => '이번 주 학식';

  @override
  String get mealToday => '오늘';

  @override
  String get mealPrevWeek => '이전 주';

  @override
  String get mealNextWeek => '다음 주';

  @override
  String mealWeekRange(DateTime start, DateTime end) {
    final intl.DateFormat startDateFormat = intl.DateFormat.MMMd(localeName);
    final String startString = startDateFormat.format(start);
    final intl.DateFormat endDateFormat = intl.DateFormat.MMMd(localeName);
    final String endString = endDateFormat.format(end);

    return '$startString – $endString';
  }

  @override
  String mealWeekdayShort(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.E(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String mealSelectedDate(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMEd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String mealDayDescription(DateTime date, String today) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMEd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString, $today';
  }

  @override
  String get mealBreakfast => '조식';

  @override
  String get mealLunch => '중식';

  @override
  String get mealDinner => '석식';

  @override
  String get mealSelectCafeteria => '식당 선택';

  @override
  String get mealKindStudent => '학생식당';

  @override
  String get mealKindDormitory => '기숙사식당';

  @override
  String get mealKindStaff => '교직원식당';

  @override
  String get mealKindOther => '식당';

  @override
  String mealCafeteriaNth(String kind, int number) {
    return '$kind $number';
  }

  @override
  String get mealEmptyTitle => '등록된 학식 메뉴가 없어요.';

  @override
  String get mealNotCollectedWeek => '이 주의 학식 정보는 아직 등록되지 않았어요.';

  @override
  String get mealNotCollectedHint => '공식 정보를 확인하면 이곳에 표시돼요.';

  @override
  String get mealClosedTitle => '이 시간에는 운영하지 않아요';

  @override
  String get mealClosedHint => '출처에서 확인된 정보예요.';

  @override
  String get mealNoMenuTitle => '공개된 메뉴가 없어요';

  @override
  String get mealNoMenuHint => '출처에서 메뉴가 공개되지 않았다고 확인된 경우예요.';

  @override
  String get mealNoCafeteria => '이 학교의 학식 정보는 아직 등록되지 않았어요.';

  @override
  String get mealLoadFailed => '학식 정보를 불러오지 못했어요';

  @override
  String get mealLoadFailedHint => '인터넷 연결을 확인하고 다시 시도해주세요.';

  @override
  String mealPrice(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return '$priceString원';
  }

  @override
  String mealServingTime(String start, String end) {
    return '운영 $start – $end';
  }

  @override
  String get mealSource => '출처';

  @override
  String get mealOpenSource => '출처 열기';

  @override
  String mealVerifiedAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '확인 $dateString';
  }

  @override
  String get mealKindMain => '메인';

  @override
  String get mealKindSide => '반찬';

  @override
  String get mealKindSoup => '국';

  @override
  String get mealKindRice => '밥';

  @override
  String get settingsAccountTitle => '계정';

  @override
  String get settingsAppTitle => '앱 설정';

  @override
  String get themeTitle => '화면 테마';

  @override
  String get themeLight => '라이트 모드';

  @override
  String get themeDark => '다크 모드';

  @override
  String get themeSystem => '시스템 설정에 따름';

  @override
  String get categoryChicken => '치킨';

  @override
  String get categoryFastFood => '패스트푸드';

  @override
  String get categoryGlobal => '세계 음식';

  @override
  String get cuisineAll => '전체';

  @override
  String get cuisineVietnamese => '베트남 음식';

  @override
  String get cuisineThai => '태국 음식';

  @override
  String get cuisineIndian => '인도 음식';

  @override
  String get cuisineMexican => '멕시코 음식';

  @override
  String get cuisineOther => '기타 세계 음식';

  @override
  String get categoryGlobalNote =>
      '카카오가 아시아음식·멕시칸 등으로 분류한 곳만 가까운 순으로 보여줘요. 가게 이름으로 나라를 추측하지 않으며, 일부 가게는 빠질 수 있어요.';

  @override
  String get cuisineEmptyHint =>
      '가까운 곳 위주로 찾고 있어서 이 학교 주변에는 없거나 검색 범위 밖일 수 있어요. 다른 종류나 학교를 선택해보세요.';

  @override
  String categoryHeading(String category) {
    return '$category 음식점';
  }

  @override
  String get categorySortDistance => '거리순';

  @override
  String get categorySortName => '이름순';

  @override
  String categoryResultCount(int count) {
    return '$count곳';
  }

  @override
  String get categoryEmptyTitle => '해당 카테고리의 맛집을 찾지 못했어요.';

  @override
  String get categoryEmptyHint => '가까운 곳 위주로 찾고 있어요. 다른 카테고리나 학교를 선택해보세요.';

  @override
  String get categoryResultsNote => '카카오 검색 결과를 가까운 순으로 보여줘요. 전체 목록이 아닐 수 있어요.';

  @override
  String get categoryAllTitle => '전체 카테고리';

  @override
  String get categoryOpenAll => '카테고리 전체 보기';

  @override
  String categoryLocation(String university, String city) {
    return '$university · $city';
  }

  @override
  String get authReasonFavorite => '로그인하면 맛집을 저장할 수 있어요';

  @override
  String get authReasonRecords => '로그인하면 먹은 음식을 기록할 수 있어요';

  @override
  String get authReasonCommunity => '로그인하면 밥수다에 글을 쓸 수 있어요';

  @override
  String get authReasonProfile => '프로필을 수정하려면 로그인이 필요해요';

  @override
  String get authPromptBody => '둘러보기와 검색은 로그인 없이도 가능해요.';

  @override
  String get authPromptLogin => '로그인';

  @override
  String get onbStepLabel => 'STEP 1–4';

  @override
  String get onbTitle => '오늘 뭐 먹지?';

  @override
  String get onbSubtitle => '나에게 맞는 맛집을 찾아볼까요?';

  @override
  String get onbCampusLabel => '현재 캠퍼스';

  @override
  String get onbBadgeRequired => '필수';

  @override
  String get onbBadgeOptional => '선택';

  @override
  String get onbBudgetTitle => '한 끼 예산';

  @override
  String get onbBudgetDesc => '모든 금액은 1인 기준이에요. ‘이상’은 특별한 날 조금 더 쓰고 싶을 때 골라요.';

  @override
  String onbBudgetMax(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '$amountString원 이하';
  }

  @override
  String onbBudgetMin(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '$amountString원 이상';
  }

  @override
  String get onbAny => '상관없어요';

  @override
  String get onbNeedBudget => '예산을 골라주세요.';

  @override
  String get onbDistanceTitle => '어디까지 갈까요?';

  @override
  String get onbDistanceDesc => '캠퍼스 기준으로 재요. 시간은 직선거리로 환산한 대략적인 값이에요.';

  @override
  String onbWalkMinutes(int minutes) {
    return '도보 $minutes분';
  }

  @override
  String onbDriveMinutes(int minutes) {
    return '차량 $minutes분';
  }

  @override
  String get onbWalkLabel => '도보';

  @override
  String get onbDriveLabel => '차량';

  @override
  String get onbNeedDistance => '거리를 골라주세요.';

  @override
  String get onbOriginTitle => '기준 위치: 캠퍼스 중심';

  @override
  String get onbOriginHint => '정문 좌표가 아직 없어서 캠퍼스 중심점에서 직선거리로 재요.';

  @override
  String get onbCompanionTitle => '누구와 먹나요?';

  @override
  String get onbCompanionDesc => '평소 누구와 식사하는지 골라주세요. 여러 개 선택할 수 있어요.';

  @override
  String get companionSolo => '혼자';

  @override
  String get companionFriends => '친구 2~3명';

  @override
  String get companionGroup => '4명 이상';

  @override
  String get companionSenior => '선배와';

  @override
  String get companionJunior => '후배와';

  @override
  String get companionProfessor => '교수님과';

  @override
  String get onbFoodTitle => '끌리는 음식';

  @override
  String get onbFoodDesc => '여러 개 골라도 돼요. 건너뛰어도 괜찮아요.';

  @override
  String get cuisineKorean => '한식';

  @override
  String get cuisineJapanese => '일식';

  @override
  String get cuisineChinese => '중식';

  @override
  String get cuisineSnack => '분식';

  @override
  String get cuisineCafe => '카페';

  @override
  String get cuisineWestern => '양식';

  @override
  String get cuisineSalad => '샐러드';

  @override
  String get cuisineAny => '상관없음';

  @override
  String get tagSpicy => '매콤한';

  @override
  String get tagHearty => '든든한';

  @override
  String get tagValue => '가성비';

  @override
  String get tagLight => '가벼운';

  @override
  String get onbUntriedTitle => '안 먹어 본 메뉴 먼저';

  @override
  String get onbUntriedDesc => '먹은 기록을 보고 최근에 먹은 종류는 뒤로 미뤄요. 기록 기능이 열리면 적용돼요.';

  @override
  String get onbFilterNote =>
      '지금은 거리와 음식 종류만 결과에 반영돼요. 예산·함께 먹는 사람·취향 태그는 가격·좌석 정보가 생기면 적용할 수 있도록 저장만 해둬요.';

  @override
  String onbCountLabel(int count) {
    return '지금 조건이면 $count곳';
  }

  @override
  String get onbCountUnknown => '주변 맛집을 불러오는 중이에요';

  @override
  String get onbCountNote => '거리·음식 종류만 반영';

  @override
  String get onbClearAll => '선택 모두 지우기';

  @override
  String get onbRandom => '랜덤';

  @override
  String get onbViewRecs => '추천 보기';

  @override
  String onbViewRecsCount(int count) {
    return '$count곳 추천 보기';
  }

  @override
  String get onbSave => '저장하기';

  @override
  String get onbRandomNone => '조건에 맞는 맛집이 없어요.';

  @override
  String get onbLogout => '로그아웃';

  @override
  String get prefsEditTitle => '나의 취향 설정';

  @override
  String get prefsEditSubtitle => '저장한 조건을 바꿀 수 있어요.';

  @override
  String get prefsSaved => '취향을 저장했어요.';

  @override
  String get prefsLoadFailed => '저장된 취향을 불러오지 못했어요';

  @override
  String get prefsSaveFailed => '저장하지 못했어요. 선택한 내용은 그대로 있으니 다시 시도해주세요.';
}
