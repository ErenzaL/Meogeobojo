import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
    Locale('zh'),
  ];

  /// No description provided for @commonRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get commonClose;

  /// No description provided for @commonLater.
  ///
  /// In ko, this message translates to:
  /// **'나중에'**
  String get commonLater;

  /// No description provided for @commonSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get commonSave;

  /// No description provided for @tryAgainLater.
  ///
  /// In ko, this message translates to:
  /// **'잠시 후 다시 시도해주세요.'**
  String get tryAgainLater;

  /// No description provided for @mascotSemantics.
  ///
  /// In ko, this message translates to:
  /// **'먹어보조 마스코트'**
  String get mascotSemantics;

  /// No description provided for @errPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'이 작업을 할 권한이 없어요. 다시 로그인한 뒤 시도해주세요.'**
  String get errPermissionDenied;

  /// No description provided for @navHome.
  ///
  /// In ko, this message translates to:
  /// **'홈'**
  String get navHome;

  /// No description provided for @navCommunity.
  ///
  /// In ko, this message translates to:
  /// **'밥수다'**
  String get navCommunity;

  /// No description provided for @navMap.
  ///
  /// In ko, this message translates to:
  /// **'지도'**
  String get navMap;

  /// No description provided for @navRecords.
  ///
  /// In ko, this message translates to:
  /// **'기록'**
  String get navRecords;

  /// No description provided for @navProfile.
  ///
  /// In ko, this message translates to:
  /// **'MY'**
  String get navProfile;

  /// No description provided for @languageSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'언어 설정'**
  String get languageSheetTitle;

  /// No description provided for @languageButtonTooltip.
  ///
  /// In ko, this message translates to:
  /// **'언어 설정'**
  String get languageButtonTooltip;

  /// No description provided for @profileLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어 설정'**
  String get profileLanguage;

  /// No description provided for @homeHeroAround.
  ///
  /// In ko, this message translates to:
  /// **'{university} 주변에서'**
  String homeHeroAround(String university);

  /// No description provided for @homeHeroTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 뭐 먹을지\n찾아볼까요?'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'맛있는 한 끼가 기다리고 있어요!'**
  String get homeHeroSubtitle;

  /// No description provided for @homeSearchLabel.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get homeSearchLabel;

  /// No description provided for @searchHint.
  ///
  /// In ko, this message translates to:
  /// **'메뉴, 식당, 키워드로 검색해보세요'**
  String get searchHint;

  /// No description provided for @homeNotificationsLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림'**
  String get homeNotificationsLabel;

  /// No description provided for @homeNotificationsSoon.
  ///
  /// In ko, this message translates to:
  /// **'알림 기능은 준비 중이에요.'**
  String get homeNotificationsSoon;

  /// No description provided for @homeMore.
  ///
  /// In ko, this message translates to:
  /// **'더보기 >'**
  String get homeMore;

  /// No description provided for @homeNearbyTitle.
  ///
  /// In ko, this message translates to:
  /// **'학교 주변 맛집'**
  String get homeNearbyTitle;

  /// No description provided for @homeMenuTitle.
  ///
  /// In ko, this message translates to:
  /// **'메뉴별로 찾아보기'**
  String get homeMenuTitle;

  /// No description provided for @homeBannerLabel.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 한 끼 추천'**
  String get homeBannerLabel;

  /// No description provided for @homeBannerTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 이거 어때요?'**
  String get homeBannerTitle;

  /// No description provided for @homeBannerSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'지금 인기 있는 맛집을 확인해보세요!'**
  String get homeBannerSubtitle;

  /// No description provided for @homeBannerCta.
  ///
  /// In ko, this message translates to:
  /// **'추천 보러가기'**
  String get homeBannerCta;

  /// No description provided for @categoryAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get categoryAll;

  /// No description provided for @categoryKorean.
  ///
  /// In ko, this message translates to:
  /// **'한식'**
  String get categoryKorean;

  /// No description provided for @categoryWestern.
  ///
  /// In ko, this message translates to:
  /// **'양식'**
  String get categoryWestern;

  /// No description provided for @categoryChinese.
  ///
  /// In ko, this message translates to:
  /// **'중식'**
  String get categoryChinese;

  /// No description provided for @categoryJapanese.
  ///
  /// In ko, this message translates to:
  /// **'일식'**
  String get categoryJapanese;

  /// No description provided for @categoryCafeDessert.
  ///
  /// In ko, this message translates to:
  /// **'카페·디저트'**
  String get categoryCafeDessert;

  /// No description provided for @categorySnack.
  ///
  /// In ko, this message translates to:
  /// **'분식'**
  String get categorySnack;

  /// No description provided for @categoryEtc.
  ///
  /// In ko, this message translates to:
  /// **'기타'**
  String get categoryEtc;

  /// No description provided for @menuMalatang.
  ///
  /// In ko, this message translates to:
  /// **'마라탕'**
  String get menuMalatang;

  /// No description provided for @menuPorkCutlet.
  ///
  /// In ko, this message translates to:
  /// **'돈까스'**
  String get menuPorkCutlet;

  /// No description provided for @menuNaengmyeon.
  ///
  /// In ko, this message translates to:
  /// **'냉면'**
  String get menuNaengmyeon;

  /// No description provided for @menuSoondubu.
  ///
  /// In ko, this message translates to:
  /// **'순두부찌개'**
  String get menuSoondubu;

  /// No description provided for @menuChicken.
  ///
  /// In ko, this message translates to:
  /// **'치킨'**
  String get menuChicken;

  /// No description provided for @menuTteokbokki.
  ///
  /// In ko, this message translates to:
  /// **'떡볶이'**
  String get menuTteokbokki;

  /// No description provided for @menuPasta.
  ///
  /// In ko, this message translates to:
  /// **'파스타'**
  String get menuPasta;

  /// No description provided for @menuAmericano.
  ///
  /// In ko, this message translates to:
  /// **'아메리카노'**
  String get menuAmericano;

  /// No description provided for @restaurantLoadFailedTitle.
  ///
  /// In ko, this message translates to:
  /// **'맛집을 불러오지 못했어요'**
  String get restaurantLoadFailedTitle;

  /// No description provided for @restaurantLoadFailedMessage.
  ///
  /// In ko, this message translates to:
  /// **'맛집 정보를 불러오지 못했어요.'**
  String get restaurantLoadFailedMessage;

  /// No description provided for @restaurantEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 주변 맛집을 찾지 못했어요'**
  String get restaurantEmptyTitle;

  /// No description provided for @universityChange.
  ///
  /// In ko, this message translates to:
  /// **'학교 바꾸기'**
  String get universityChange;

  /// No description provided for @restaurantListSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'{university} · {category} · 가까운 순'**
  String restaurantListSubtitle(String university, String category);

  /// No description provided for @restaurantTagDistance.
  ///
  /// In ko, this message translates to:
  /// **'{tag} · 학교에서 {distance}'**
  String restaurantTagDistance(String tag, String distance);

  /// No description provided for @restaurantDistanceFromSchool.
  ///
  /// In ko, this message translates to:
  /// **'학교에서 {distance}'**
  String restaurantDistanceFromSchool(String distance);

  /// No description provided for @restaurantDistanceStraight.
  ///
  /// In ko, this message translates to:
  /// **'학교에서 {distance} (직선거리)'**
  String restaurantDistanceStraight(String distance);

  /// No description provided for @restaurantNoAddress.
  ///
  /// In ko, this message translates to:
  /// **'주소 정보가 없어요'**
  String get restaurantNoAddress;

  /// No description provided for @restaurantNoPhone.
  ///
  /// In ko, this message translates to:
  /// **'등록된 전화번호가 없어요'**
  String get restaurantNoPhone;

  /// No description provided for @restaurantDataNotice.
  ///
  /// In ko, this message translates to:
  /// **'사진, 평점, 메뉴·가격, 영업시간은 아직 제공되지 않아요. 자세한 정보는 카카오맵에서 확인해보세요.'**
  String get restaurantDataNotice;

  /// No description provided for @restaurantOpenKakaoMap.
  ///
  /// In ko, this message translates to:
  /// **'카카오맵에서 보기'**
  String get restaurantOpenKakaoMap;

  /// No description provided for @restaurantLinkOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'열 수 없는 링크예요.'**
  String get restaurantLinkOpenFailed;

  /// No description provided for @restaurantErrNetwork.
  ///
  /// In ko, this message translates to:
  /// **'인터넷 연결을 확인해주세요.'**
  String get restaurantErrNetwork;

  /// No description provided for @restaurantErrTimeout.
  ///
  /// In ko, this message translates to:
  /// **'응답이 너무 늦어지고 있어요. 잠시 후 다시 시도해주세요.'**
  String get restaurantErrTimeout;

  /// No description provided for @restaurantErrQuota.
  ///
  /// In ko, this message translates to:
  /// **'요청이 많아 잠시 후 다시 시도해주세요.'**
  String get restaurantErrQuota;

  /// No description provided for @restaurantErrAuth.
  ///
  /// In ko, this message translates to:
  /// **'맛집 검색 서버 인증에 실패했어요.'**
  String get restaurantErrAuth;

  /// No description provided for @restaurantErrInvalid.
  ///
  /// In ko, this message translates to:
  /// **'검색 조건이 올바르지 않아요.'**
  String get restaurantErrInvalid;

  /// No description provided for @restaurantErrUpstream.
  ///
  /// In ko, this message translates to:
  /// **'맛집 정보를 가져오는 중 서버에 문제가 생겼어요.'**
  String get restaurantErrUpstream;

  /// No description provided for @restaurantErrUnknown.
  ///
  /// In ko, this message translates to:
  /// **'알 수 없는 오류가 발생했어요.'**
  String get restaurantErrUnknown;

  /// No description provided for @searchIdleTitle.
  ///
  /// In ko, this message translates to:
  /// **'무엇을 먹고 싶으세요?'**
  String get searchIdleTitle;

  /// No description provided for @searchIdleMessage.
  ///
  /// In ko, this message translates to:
  /// **'{university} 주변에서 찾아드릴게요.'**
  String searchIdleMessage(String university);

  /// No description provided for @searchNoResultsTitle.
  ///
  /// In ko, this message translates to:
  /// **'\'{query}\' 검색 결과가 없어요'**
  String searchNoResultsTitle(String query);

  /// No description provided for @searchNoResultsMessage.
  ///
  /// In ko, this message translates to:
  /// **'다른 키워드로 검색하거나 학교를 바꿔보세요.'**
  String get searchNoResultsMessage;

  /// No description provided for @searchResultsSummary.
  ///
  /// In ko, this message translates to:
  /// **'{university} 주변 · 가까운 순 {count}곳'**
  String searchResultsSummary(String university, int count);

  /// No description provided for @mapStatusLoading.
  ///
  /// In ko, this message translates to:
  /// **'{university} · 맛집 불러오는 중…'**
  String mapStatusLoading(String university);

  /// No description provided for @mapStatusError.
  ///
  /// In ko, this message translates to:
  /// **'{university} · 맛집을 불러오지 못했어요'**
  String mapStatusError(String university);

  /// No description provided for @mapStatusCount.
  ///
  /// In ko, this message translates to:
  /// **'{university} · 주변 {count}곳'**
  String mapStatusCount(String university, int count);

  /// No description provided for @mapErrorTitle.
  ///
  /// In ko, this message translates to:
  /// **'지도를 불러오지 못했어요'**
  String get mapErrorTitle;

  /// No description provided for @mapErrorMessage.
  ///
  /// In ko, this message translates to:
  /// **'잠시 후 다시 시도해주세요. 맛집 목록과 검색은 계속 사용할 수 있어요.'**
  String get mapErrorMessage;

  /// No description provided for @universitySelect.
  ///
  /// In ko, this message translates to:
  /// **'학교 선택'**
  String get universitySelect;

  /// No description provided for @universitySelectCurrent.
  ///
  /// In ko, this message translates to:
  /// **'학교 선택, 현재 {name}'**
  String universitySelectCurrent(String name);

  /// No description provided for @universitySearchHint.
  ///
  /// In ko, this message translates to:
  /// **'학교 이름 검색'**
  String get universitySearchHint;

  /// No description provided for @universityLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'학교 목록을 불러오지 못했어요'**
  String get universityLoadFailed;

  /// No description provided for @universityNoMatch.
  ///
  /// In ko, this message translates to:
  /// **'일치하는 학교가 없어요'**
  String get universityNoMatch;

  /// No description provided for @universityFallbackName.
  ///
  /// In ko, this message translates to:
  /// **'학교'**
  String get universityFallbackName;

  /// No description provided for @cityAsan.
  ///
  /// In ko, this message translates to:
  /// **'아산'**
  String get cityAsan;

  /// No description provided for @cityCheonan.
  ///
  /// In ko, this message translates to:
  /// **'천안'**
  String get cityCheonan;

  /// No description provided for @favoriteAdd.
  ///
  /// In ko, this message translates to:
  /// **'즐겨찾기 추가'**
  String get favoriteAdd;

  /// No description provided for @favoriteRemove.
  ///
  /// In ko, this message translates to:
  /// **'즐겨찾기 해제'**
  String get favoriteRemove;

  /// No description provided for @favoriteSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'즐겨찾기를 저장하지 못했어요. 잠시 후 다시 시도해주세요.'**
  String get favoriteSaveFailed;

  /// No description provided for @recordsEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 기록이 없어요'**
  String get recordsEmptyTitle;

  /// No description provided for @recordsEmptyMessage.
  ///
  /// In ko, this message translates to:
  /// **'먹은 음식을 기록하는 기능은 준비 중이에요.'**
  String get recordsEmptyMessage;

  /// No description provided for @communityTitle.
  ///
  /// In ko, this message translates to:
  /// **'밥수다는 준비 중이에요'**
  String get communityTitle;

  /// No description provided for @communityMessage.
  ///
  /// In ko, this message translates to:
  /// **'같은 학교 친구들과 맛집 이야기를 나눌 수 있도록\n열심히 만들고 있어요!'**
  String get communityMessage;

  /// No description provided for @recommendStrategyProximity.
  ///
  /// In ko, this message translates to:
  /// **'{university}에서 가까운 순'**
  String recommendStrategyProximity(String university);

  /// No description provided for @recommendExplainBaseline.
  ///
  /// In ko, this message translates to:
  /// **'아직 인기·취향 데이터가 없어서 학교에서 가까운 음식점부터 보여드려요. 맞춤 추천은 준비 중이에요.'**
  String get recommendExplainBaseline;

  /// No description provided for @recommendStrategyPreferences.
  ///
  /// In ko, this message translates to:
  /// **'내 조건으로 거른 결과'**
  String get recommendStrategyPreferences;

  /// No description provided for @recommendExplainPreferences.
  ///
  /// In ko, this message translates to:
  /// **'저장한 거리·음식 종류 조건을 적용해 {total}곳 중 {count}곳을 가까운 순으로 보여드려요. 예산·함께 먹는 사람·취향 태그는 아직 반영되지 않고, 거리는 직선거리 기준 근사치예요. 맞춤 추천은 준비 중이에요.'**
  String recommendExplainPreferences(int count, int total);

  /// No description provided for @recommendNoMatchTitle.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 맛집이 없어요'**
  String get recommendNoMatchTitle;

  /// No description provided for @recommendNoMatchMessage.
  ///
  /// In ko, this message translates to:
  /// **'거리나 음식 종류 조건을 바꿔보세요.'**
  String get recommendNoMatchMessage;

  /// No description provided for @profileGuestTitle.
  ///
  /// In ko, this message translates to:
  /// **'로그인하고 맛집을 저장해보세요'**
  String get profileGuestTitle;

  /// No description provided for @profileGuestSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'둘러보기와 검색은 로그인 없이도 가능해요.'**
  String get profileGuestSubtitle;

  /// No description provided for @profileLoginButton.
  ///
  /// In ko, this message translates to:
  /// **'로그인 / 회원가입'**
  String get profileLoginButton;

  /// No description provided for @profileGreeting.
  ///
  /// In ko, this message translates to:
  /// **'안녕하세요, {nickname}님'**
  String profileGreeting(String nickname);

  /// No description provided for @profileGreetingSub.
  ///
  /// In ko, this message translates to:
  /// **'오늘도 맛있는 한 끼 찾아볼까요?'**
  String get profileGreetingSub;

  /// No description provided for @profileEditProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필 수정 →'**
  String get profileEditProfile;

  /// No description provided for @profileCampusHint.
  ///
  /// In ko, this message translates to:
  /// **'{city} · 탭해서 학교 바꾸기'**
  String profileCampusHint(String city);

  /// No description provided for @profileCampusHintNoCity.
  ///
  /// In ko, this message translates to:
  /// **'탭해서 학교 바꾸기'**
  String get profileCampusHintNoCity;

  /// No description provided for @profileStatSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장한 맛집'**
  String get profileStatSaved;

  /// No description provided for @profileStatRecords.
  ///
  /// In ko, this message translates to:
  /// **'나의 기록'**
  String get profileStatRecords;

  /// No description provided for @profileStatPlans.
  ///
  /// In ko, this message translates to:
  /// **'예정된 약속'**
  String get profileStatPlans;

  /// No description provided for @profileStatUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'준비 중'**
  String get profileStatUnavailable;

  /// No description provided for @profileSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장한 맛집'**
  String get profileSaved;

  /// No description provided for @profileSavedCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}곳'**
  String profileSavedCount(int count);

  /// No description provided for @profileRecords.
  ///
  /// In ko, this message translates to:
  /// **'나의 기록'**
  String get profileRecords;

  /// No description provided for @profilePreferences.
  ///
  /// In ko, this message translates to:
  /// **'나의 취향 설정'**
  String get profilePreferences;

  /// No description provided for @profileAccount.
  ///
  /// In ko, this message translates to:
  /// **'계정 설정'**
  String get profileAccount;

  /// No description provided for @profileLogout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get profileLogout;

  /// No description provided for @profileDefaultNickname.
  ///
  /// In ko, this message translates to:
  /// **'먹어보조 사용자'**
  String get profileDefaultNickname;

  /// No description provided for @savedLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장한 맛집을 불러오지 못했어요'**
  String get savedLoadFailed;

  /// No description provided for @savedEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 저장한 맛집이 없어요'**
  String get savedEmptyTitle;

  /// No description provided for @savedEmptyMessage.
  ///
  /// In ko, this message translates to:
  /// **'마음에 드는 식당의 하트를 눌러 저장해보세요.'**
  String get savedEmptyMessage;

  /// No description provided for @savedCount.
  ///
  /// In ko, this message translates to:
  /// **'저장한 맛집 {count}곳'**
  String savedCount(int count);

  /// No description provided for @savedHiddenNote.
  ///
  /// In ko, this message translates to:
  /// **'{count}곳은 지금 선택한 학교 주변 목록에 없어 자세한 정보를 보여드릴 수 없어요. 해당 학교를 선택하면 볼 수 있어요.'**
  String savedHiddenNote(int count);

  /// No description provided for @accountNickname.
  ///
  /// In ko, this message translates to:
  /// **'닉네임'**
  String get accountNickname;

  /// No description provided for @accountNicknameEdit.
  ///
  /// In ko, this message translates to:
  /// **'닉네임 변경'**
  String get accountNicknameEdit;

  /// No description provided for @accountEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get accountEmail;

  /// No description provided for @accountLoginMethod.
  ///
  /// In ko, this message translates to:
  /// **'로그인 방식'**
  String get accountLoginMethod;

  /// No description provided for @accountProviderKakao.
  ///
  /// In ko, this message translates to:
  /// **'카카오'**
  String get accountProviderKakao;

  /// No description provided for @accountProviderEmail.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get accountProviderEmail;

  /// No description provided for @authWelcomeTitle.
  ///
  /// In ko, this message translates to:
  /// **'먹어보조에 오신 걸 환영해요!'**
  String get authWelcomeTitle;

  /// No description provided for @authWelcomeSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'로그인하고 나만의 맛집을 찾아보세요.'**
  String get authWelcomeSubtitle;

  /// No description provided for @authContinueKakao.
  ///
  /// In ko, this message translates to:
  /// **'카카오로 계속하기'**
  String get authContinueKakao;

  /// No description provided for @authEmailLogin.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 로그인'**
  String get authEmailLogin;

  /// No description provided for @authEmailSignUp.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 회원가입'**
  String get authEmailSignUp;

  /// No description provided for @authBrowseAsGuest.
  ///
  /// In ko, this message translates to:
  /// **'로그인 없이 계속 둘러보기 →'**
  String get authBrowseAsGuest;

  /// No description provided for @authKakaoWaiting.
  ///
  /// In ko, this message translates to:
  /// **'카카오 로그인 진행 중…'**
  String get authKakaoWaiting;

  /// No description provided for @legalTerms.
  ///
  /// In ko, this message translates to:
  /// **'이용약관'**
  String get legalTerms;

  /// No description provided for @legalPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'개인정보처리방침'**
  String get legalPrivacy;

  /// No description provided for @legalNotPublished.
  ///
  /// In ko, this message translates to:
  /// **'문서가 아직 게시되지 않았어요.'**
  String get legalNotPublished;

  /// No description provided for @legalOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'링크를 열 수 없어요.'**
  String get legalOpenFailed;

  /// No description provided for @authEmailLoginTitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 로그인'**
  String get authEmailLoginTitle;

  /// No description provided for @authEmailLabel.
  ///
  /// In ko, this message translates to:
  /// **'이메일'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordConfirmLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 확인'**
  String get authPasswordConfirmLabel;

  /// No description provided for @authNewPasswordLabel.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호'**
  String get authNewPasswordLabel;

  /// No description provided for @authPasswordShow.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 보기'**
  String get authPasswordShow;

  /// No description provided for @authPasswordHide.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 숨기기'**
  String get authPasswordHide;

  /// No description provided for @authLoginButton.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get authLoginButton;

  /// No description provided for @authForgotPasswordLink.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 잊으셨나요?'**
  String get authForgotPasswordLink;

  /// No description provided for @authNoAccountSignUp.
  ///
  /// In ko, this message translates to:
  /// **'아직 계정이 없나요? 회원가입'**
  String get authNoAccountSignUp;

  /// No description provided for @authHaveAccountLogin.
  ///
  /// In ko, this message translates to:
  /// **'이미 계정이 있어요. 로그인'**
  String get authHaveAccountLogin;

  /// No description provided for @authSignUpTitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일로 회원가입'**
  String get authSignUpTitle;

  /// No description provided for @authSignUpSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일과 비밀번호로 계정을 만들어요. 가입 후 이메일 인증이 필요해요.'**
  String get authSignUpSubtitle;

  /// No description provided for @authSignUpButton.
  ///
  /// In ko, this message translates to:
  /// **'가입하기'**
  String get authSignUpButton;

  /// No description provided for @authPasswordRule.
  ///
  /// In ko, this message translates to:
  /// **'{min}자 이상 입력해주세요.'**
  String authPasswordRule(int min);

  /// No description provided for @authVerifyTitle.
  ///
  /// In ko, this message translates to:
  /// **'이메일을 확인해주세요'**
  String get authVerifyTitle;

  /// No description provided for @authVerifyMessage.
  ///
  /// In ko, this message translates to:
  /// **'{email}(으)로 인증 메일을 보냈어요. 메일의 링크를 누르면 가입이 완료돼요.'**
  String authVerifyMessage(String email);

  /// No description provided for @authVerifyNotSignedIn.
  ///
  /// In ko, this message translates to:
  /// **'인증을 마치기 전까지는 로그인되지 않아요.'**
  String get authVerifyNotSignedIn;

  /// No description provided for @authVerifyResend.
  ///
  /// In ko, this message translates to:
  /// **'인증 메일 다시 받기'**
  String get authVerifyResend;

  /// No description provided for @authVerifyResendIn.
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초 뒤에 다시 보낼 수 있어요'**
  String authVerifyResendIn(int seconds);

  /// No description provided for @authVerifyResent.
  ///
  /// In ko, this message translates to:
  /// **'인증 메일을 다시 보냈어요.'**
  String get authVerifyResent;

  /// No description provided for @authVerifyBackToLogin.
  ///
  /// In ko, this message translates to:
  /// **'로그인으로 돌아가기'**
  String get authVerifyBackToLogin;

  /// No description provided for @authForgotTitle.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 찾기'**
  String get authForgotTitle;

  /// No description provided for @authForgotMessage.
  ///
  /// In ko, this message translates to:
  /// **'가입한 이메일을 입력하면 비밀번호 재설정 링크를 보내드려요.'**
  String get authForgotMessage;

  /// No description provided for @authForgotSend.
  ///
  /// In ko, this message translates to:
  /// **'재설정 메일 보내기'**
  String get authForgotSend;

  /// No description provided for @authForgotResend.
  ///
  /// In ko, this message translates to:
  /// **'다시 보내기'**
  String get authForgotResend;

  /// No description provided for @authForgotSent.
  ///
  /// In ko, this message translates to:
  /// **'가입된 이메일이라면 {email}(으)로 재설정 링크를 보냈어요. 메일함을 확인해주세요.'**
  String authForgotSent(String email);

  /// No description provided for @authResetTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 비밀번호 설정'**
  String get authResetTitle;

  /// No description provided for @authResetMessage.
  ///
  /// In ko, this message translates to:
  /// **'새로 사용할 비밀번호를 입력해주세요.'**
  String get authResetMessage;

  /// No description provided for @authResetButton.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 변경하기'**
  String get authResetButton;

  /// No description provided for @authResetSuccess.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 변경했어요.'**
  String get authResetSuccess;

  /// No description provided for @errEmailRequired.
  ///
  /// In ko, this message translates to:
  /// **'이메일을 입력해주세요.'**
  String get errEmailRequired;

  /// No description provided for @errEmailInvalid.
  ///
  /// In ko, this message translates to:
  /// **'올바른 이메일 형식이 아니에요.'**
  String get errEmailInvalid;

  /// No description provided for @errPasswordRequired.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호를 입력해주세요.'**
  String get errPasswordRequired;

  /// No description provided for @errPasswordShort.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호는 {min}자 이상이어야 해요.'**
  String errPasswordShort(int min);

  /// No description provided for @errPasswordMismatch.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 서로 달라요.'**
  String get errPasswordMismatch;

  /// No description provided for @authErrInvalidCredentials.
  ///
  /// In ko, this message translates to:
  /// **'이메일 또는 비밀번호가 올바르지 않아요.'**
  String get authErrInvalidCredentials;

  /// No description provided for @authErrEmailNotConfirmed.
  ///
  /// In ko, this message translates to:
  /// **'이메일 인증이 아직 완료되지 않았어요. 메일의 링크를 눌러 인증해주세요.'**
  String get authErrEmailNotConfirmed;

  /// No description provided for @authErrEmailTaken.
  ///
  /// In ko, this message translates to:
  /// **'이미 가입된 이메일이에요. 로그인해주세요.'**
  String get authErrEmailTaken;

  /// No description provided for @authErrInvalidEmail.
  ///
  /// In ko, this message translates to:
  /// **'올바른 이메일 형식이 아니에요.'**
  String get authErrInvalidEmail;

  /// No description provided for @authErrWeakPassword.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호가 너무 약해요. 더 길고 복잡하게 만들어주세요.'**
  String get authErrWeakPassword;

  /// No description provided for @authErrSamePassword.
  ///
  /// In ko, this message translates to:
  /// **'이전과 다른 비밀번호를 사용해주세요.'**
  String get authErrSamePassword;

  /// No description provided for @authErrKakaoCancelled.
  ///
  /// In ko, this message translates to:
  /// **'카카오 로그인을 취소했어요.'**
  String get authErrKakaoCancelled;

  /// No description provided for @authErrKakaoConfig.
  ///
  /// In ko, this message translates to:
  /// **'카카오 로그인 설정에 문제가 있어요. 잠시 후 다시 시도하고, 계속되면 문의해주세요.'**
  String get authErrKakaoConfig;

  /// No description provided for @authErrDeepLinkMissing.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 완료되지 않았어요. 취소했거나 앱으로 돌아오지 못했을 수 있어요. 다시 시도해주세요.'**
  String get authErrDeepLinkMissing;

  /// No description provided for @authErrSessionExpired.
  ///
  /// In ko, this message translates to:
  /// **'로그인이 만료됐어요. 다시 로그인해주세요.'**
  String get authErrSessionExpired;

  /// No description provided for @authErrLinkExpired.
  ///
  /// In ko, this message translates to:
  /// **'링크가 만료됐거나 이미 사용됐어요. 새 링크를 요청해주세요.'**
  String get authErrLinkExpired;

  /// No description provided for @authErrRateLimited.
  ///
  /// In ko, this message translates to:
  /// **'요청이 너무 많아요. 잠시 후 다시 시도해주세요.'**
  String get authErrRateLimited;

  /// No description provided for @authErrNetwork.
  ///
  /// In ko, this message translates to:
  /// **'인터넷 연결을 확인하고 다시 시도해주세요.'**
  String get authErrNetwork;

  /// No description provided for @authErrTimeout.
  ///
  /// In ko, this message translates to:
  /// **'응답이 너무 늦어요. 잠시 후 다시 시도해주세요.'**
  String get authErrTimeout;

  /// No description provided for @authErrPasswordReset.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호 재설정에 실패했어요. 다시 시도해주세요.'**
  String get authErrPasswordReset;

  /// No description provided for @authErrProfileLoad.
  ///
  /// In ko, this message translates to:
  /// **'내 정보를 불러오지 못했어요. 다시 시도해주세요.'**
  String get authErrProfileLoad;

  /// No description provided for @authErrUnknown.
  ///
  /// In ko, this message translates to:
  /// **'문제가 생겼어요. 잠시 후 다시 시도해주세요.'**
  String get authErrUnknown;

  /// No description provided for @nicknameSetupTitle.
  ///
  /// In ko, this message translates to:
  /// **'어떻게 불러드릴까요?'**
  String get nicknameSetupTitle;

  /// No description provided for @nicknameSetupSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'먹어보조에서 사용할 닉네임을 정해주세요.'**
  String get nicknameSetupSubtitle;

  /// No description provided for @nicknameLabel.
  ///
  /// In ko, this message translates to:
  /// **'닉네임'**
  String get nicknameLabel;

  /// No description provided for @nicknameHint.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 입력해주세요'**
  String get nicknameHint;

  /// No description provided for @nicknameNext.
  ///
  /// In ko, this message translates to:
  /// **'다음'**
  String get nicknameNext;

  /// No description provided for @nicknameRule.
  ///
  /// In ko, this message translates to:
  /// **'{min}~{max}자로 입력해주세요.'**
  String nicknameRule(int min, int max);

  /// No description provided for @nicknameErrEmpty.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 입력해주세요.'**
  String get nicknameErrEmpty;

  /// No description provided for @nicknameErrTooShort.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 {min}자 이상이어야 해요.'**
  String nicknameErrTooShort(int min);

  /// No description provided for @nicknameErrTooLong.
  ///
  /// In ko, this message translates to:
  /// **'닉네임은 {max}자 이하여야 해요.'**
  String nicknameErrTooLong(int max);

  /// No description provided for @nicknameErrInvalidChars.
  ///
  /// In ko, this message translates to:
  /// **'사용할 수 없는 문자가 포함되어 있어요.'**
  String get nicknameErrInvalidChars;

  /// No description provided for @nicknameSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 저장하지 못했어요. 다시 시도해주세요.'**
  String get nicknameSaveFailed;

  /// No description provided for @nicknameUpdated.
  ///
  /// In ko, this message translates to:
  /// **'닉네임을 변경했어요.'**
  String get nicknameUpdated;

  /// No description provided for @homeCampusMeals.
  ///
  /// In ko, this message translates to:
  /// **'학식'**
  String get homeCampusMeals;

  /// No description provided for @mealPageTitle.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 학식'**
  String get mealPageTitle;

  /// No description provided for @mealToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get mealToday;

  /// No description provided for @mealPrevWeek.
  ///
  /// In ko, this message translates to:
  /// **'이전 주'**
  String get mealPrevWeek;

  /// No description provided for @mealNextWeek.
  ///
  /// In ko, this message translates to:
  /// **'다음 주'**
  String get mealNextWeek;

  /// No description provided for @mealWeekRange.
  ///
  /// In ko, this message translates to:
  /// **'{start} – {end}'**
  String mealWeekRange(DateTime start, DateTime end);

  /// No description provided for @mealWeekdayShort.
  ///
  /// In ko, this message translates to:
  /// **'{date}'**
  String mealWeekdayShort(DateTime date);

  /// No description provided for @mealSelectedDate.
  ///
  /// In ko, this message translates to:
  /// **'{date}'**
  String mealSelectedDate(DateTime date);

  /// No description provided for @mealDayDescription.
  ///
  /// In ko, this message translates to:
  /// **'{date}, {today}'**
  String mealDayDescription(DateTime date, String today);

  /// No description provided for @mealBreakfast.
  ///
  /// In ko, this message translates to:
  /// **'조식'**
  String get mealBreakfast;

  /// No description provided for @mealLunch.
  ///
  /// In ko, this message translates to:
  /// **'중식'**
  String get mealLunch;

  /// No description provided for @mealDinner.
  ///
  /// In ko, this message translates to:
  /// **'석식'**
  String get mealDinner;

  /// No description provided for @mealSelectCafeteria.
  ///
  /// In ko, this message translates to:
  /// **'식당 선택'**
  String get mealSelectCafeteria;

  /// No description provided for @mealKindStudent.
  ///
  /// In ko, this message translates to:
  /// **'학생식당'**
  String get mealKindStudent;

  /// No description provided for @mealKindDormitory.
  ///
  /// In ko, this message translates to:
  /// **'기숙사식당'**
  String get mealKindDormitory;

  /// No description provided for @mealKindStaff.
  ///
  /// In ko, this message translates to:
  /// **'교직원식당'**
  String get mealKindStaff;

  /// No description provided for @mealKindOther.
  ///
  /// In ko, this message translates to:
  /// **'식당'**
  String get mealKindOther;

  /// No description provided for @mealCafeteriaNth.
  ///
  /// In ko, this message translates to:
  /// **'{kind} {number}'**
  String mealCafeteriaNth(String kind, int number);

  /// No description provided for @mealEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'등록된 식단 정보가 없습니다.'**
  String get mealEmptyTitle;

  /// No description provided for @mealNotCollectedWeek.
  ///
  /// In ko, this message translates to:
  /// **'이 주의 학식 정보는 아직 등록되지 않았어요.'**
  String get mealNotCollectedWeek;

  /// No description provided for @mealNotCollectedHint.
  ///
  /// In ko, this message translates to:
  /// **'공식 정보를 확인하면 이곳에 표시돼요.'**
  String get mealNotCollectedHint;

  /// No description provided for @mealClosedTitle.
  ///
  /// In ko, this message translates to:
  /// **'이 시간에는 운영하지 않아요'**
  String get mealClosedTitle;

  /// No description provided for @mealClosedHint.
  ///
  /// In ko, this message translates to:
  /// **'출처에서 확인된 정보예요.'**
  String get mealClosedHint;

  /// No description provided for @mealNoMenuTitle.
  ///
  /// In ko, this message translates to:
  /// **'공개된 메뉴가 없어요'**
  String get mealNoMenuTitle;

  /// No description provided for @mealNoMenuHint.
  ///
  /// In ko, this message translates to:
  /// **'출처에서 메뉴가 공개되지 않았다고 확인된 경우예요.'**
  String get mealNoMenuHint;

  /// No description provided for @mealNoCafeteria.
  ///
  /// In ko, this message translates to:
  /// **'이 학교의 학식 정보는 아직 등록되지 않았어요.'**
  String get mealNoCafeteria;

  /// No description provided for @mealLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'학식 정보를 불러오지 못했어요'**
  String get mealLoadFailed;

  /// No description provided for @mealLoadFailedHint.
  ///
  /// In ko, this message translates to:
  /// **'인터넷 연결을 확인하고 다시 시도해주세요.'**
  String get mealLoadFailedHint;

  /// No description provided for @mealPrice.
  ///
  /// In ko, this message translates to:
  /// **'{price}원'**
  String mealPrice(int price);

  /// No description provided for @mealServingTime.
  ///
  /// In ko, this message translates to:
  /// **'운영 {start} – {end}'**
  String mealServingTime(String start, String end);

  /// No description provided for @mealSource.
  ///
  /// In ko, this message translates to:
  /// **'출처'**
  String get mealSource;

  /// No description provided for @mealOpenSource.
  ///
  /// In ko, this message translates to:
  /// **'출처 열기'**
  String get mealOpenSource;

  /// No description provided for @mealVerifiedAt.
  ///
  /// In ko, this message translates to:
  /// **'확인 {date}'**
  String mealVerifiedAt(DateTime date);

  /// No description provided for @mealKindMain.
  ///
  /// In ko, this message translates to:
  /// **'메인'**
  String get mealKindMain;

  /// No description provided for @mealKindSide.
  ///
  /// In ko, this message translates to:
  /// **'반찬'**
  String get mealKindSide;

  /// No description provided for @mealKindSoup.
  ///
  /// In ko, this message translates to:
  /// **'국'**
  String get mealKindSoup;

  /// No description provided for @mealKindRice.
  ///
  /// In ko, this message translates to:
  /// **'밥'**
  String get mealKindRice;

  /// No description provided for @settingsAccountTitle.
  ///
  /// In ko, this message translates to:
  /// **'계정'**
  String get settingsAccountTitle;

  /// No description provided for @settingsAppTitle.
  ///
  /// In ko, this message translates to:
  /// **'앱 설정'**
  String get settingsAppTitle;

  /// No description provided for @themeTitle.
  ///
  /// In ko, this message translates to:
  /// **'화면 테마'**
  String get themeTitle;

  /// No description provided for @themeLight.
  ///
  /// In ko, this message translates to:
  /// **'라이트 모드'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ko, this message translates to:
  /// **'다크 모드'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정에 따름'**
  String get themeSystem;

  /// No description provided for @categoryChicken.
  ///
  /// In ko, this message translates to:
  /// **'치킨'**
  String get categoryChicken;

  /// No description provided for @categoryFastFood.
  ///
  /// In ko, this message translates to:
  /// **'패스트푸드'**
  String get categoryFastFood;

  /// No description provided for @categoryGlobal.
  ///
  /// In ko, this message translates to:
  /// **'세계 음식'**
  String get categoryGlobal;

  /// No description provided for @cuisineAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get cuisineAll;

  /// No description provided for @cuisineVietnamese.
  ///
  /// In ko, this message translates to:
  /// **'베트남 음식'**
  String get cuisineVietnamese;

  /// No description provided for @cuisineThai.
  ///
  /// In ko, this message translates to:
  /// **'태국 음식'**
  String get cuisineThai;

  /// No description provided for @cuisineIndian.
  ///
  /// In ko, this message translates to:
  /// **'인도 음식'**
  String get cuisineIndian;

  /// No description provided for @cuisineMexican.
  ///
  /// In ko, this message translates to:
  /// **'멕시코 음식'**
  String get cuisineMexican;

  /// No description provided for @cuisineOther.
  ///
  /// In ko, this message translates to:
  /// **'기타 세계 음식'**
  String get cuisineOther;

  /// No description provided for @categoryGlobalNote.
  ///
  /// In ko, this message translates to:
  /// **'카카오가 아시아음식·멕시칸 등으로 분류한 곳만 가까운 순으로 보여줘요. 가게 이름으로 나라를 추측하지 않으며, 일부 가게는 빠질 수 있어요.'**
  String get categoryGlobalNote;

  /// No description provided for @cuisineEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'가까운 곳 위주로 찾고 있어서 이 학교 주변에는 없거나 검색 범위 밖일 수 있어요. 다른 종류나 학교를 선택해보세요.'**
  String get cuisineEmptyHint;

  /// No description provided for @categoryHeading.
  ///
  /// In ko, this message translates to:
  /// **'{category} 음식점'**
  String categoryHeading(String category);

  /// No description provided for @categorySortDistance.
  ///
  /// In ko, this message translates to:
  /// **'거리순'**
  String get categorySortDistance;

  /// No description provided for @categorySortName.
  ///
  /// In ko, this message translates to:
  /// **'이름순'**
  String get categorySortName;

  /// No description provided for @categoryResultCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}곳'**
  String categoryResultCount(int count);

  /// No description provided for @categoryEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'해당 카테고리의 맛집을 찾지 못했어요.'**
  String get categoryEmptyTitle;

  /// No description provided for @categoryEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'가까운 곳 위주로 찾고 있어요. 다른 카테고리나 학교를 선택해보세요.'**
  String get categoryEmptyHint;

  /// No description provided for @categoryResultsNote.
  ///
  /// In ko, this message translates to:
  /// **'카카오 검색 결과를 가까운 순으로 보여줘요. 전체 목록이 아닐 수 있어요.'**
  String get categoryResultsNote;

  /// No description provided for @categoryAllTitle.
  ///
  /// In ko, this message translates to:
  /// **'전체 카테고리'**
  String get categoryAllTitle;

  /// No description provided for @categoryOpenAll.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 전체 보기'**
  String get categoryOpenAll;

  /// No description provided for @categoryLocation.
  ///
  /// In ko, this message translates to:
  /// **'{university} · {city}'**
  String categoryLocation(String university, String city);

  /// No description provided for @authReasonFavorite.
  ///
  /// In ko, this message translates to:
  /// **'로그인하면 맛집을 저장할 수 있어요'**
  String get authReasonFavorite;

  /// No description provided for @authReasonRecords.
  ///
  /// In ko, this message translates to:
  /// **'로그인하면 먹은 음식을 기록할 수 있어요'**
  String get authReasonRecords;

  /// No description provided for @authReasonCommunity.
  ///
  /// In ko, this message translates to:
  /// **'로그인하면 밥수다에 글을 쓸 수 있어요'**
  String get authReasonCommunity;

  /// No description provided for @authReasonProfile.
  ///
  /// In ko, this message translates to:
  /// **'프로필을 수정하려면 로그인이 필요해요'**
  String get authReasonProfile;

  /// No description provided for @authPromptBody.
  ///
  /// In ko, this message translates to:
  /// **'둘러보기와 검색은 로그인 없이도 가능해요.'**
  String get authPromptBody;

  /// No description provided for @authPromptLogin.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get authPromptLogin;

  /// No description provided for @onbStepLabel.
  ///
  /// In ko, this message translates to:
  /// **'STEP 1–4'**
  String get onbStepLabel;

  /// No description provided for @onbTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 뭐 먹지?'**
  String get onbTitle;

  /// No description provided for @onbSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'나에게 맞는 맛집을 찾아볼까요?'**
  String get onbSubtitle;

  /// No description provided for @onbCampusLabel.
  ///
  /// In ko, this message translates to:
  /// **'현재 캠퍼스'**
  String get onbCampusLabel;

  /// No description provided for @onbBadgeRequired.
  ///
  /// In ko, this message translates to:
  /// **'필수'**
  String get onbBadgeRequired;

  /// No description provided for @onbBadgeOptional.
  ///
  /// In ko, this message translates to:
  /// **'선택'**
  String get onbBadgeOptional;

  /// No description provided for @onbBudgetTitle.
  ///
  /// In ko, this message translates to:
  /// **'한 끼 예산'**
  String get onbBudgetTitle;

  /// No description provided for @onbBudgetDesc.
  ///
  /// In ko, this message translates to:
  /// **'모든 금액은 1인 기준이에요. ‘이상’은 특별한 날 조금 더 쓰고 싶을 때 골라요.'**
  String get onbBudgetDesc;

  /// No description provided for @onbBudgetMax.
  ///
  /// In ko, this message translates to:
  /// **'{amount}원 이하'**
  String onbBudgetMax(int amount);

  /// No description provided for @onbBudgetMin.
  ///
  /// In ko, this message translates to:
  /// **'{amount}원 이상'**
  String onbBudgetMin(int amount);

  /// No description provided for @onbAny.
  ///
  /// In ko, this message translates to:
  /// **'상관없어요'**
  String get onbAny;

  /// No description provided for @onbNeedBudget.
  ///
  /// In ko, this message translates to:
  /// **'예산을 골라주세요.'**
  String get onbNeedBudget;

  /// No description provided for @onbDistanceTitle.
  ///
  /// In ko, this message translates to:
  /// **'어디까지 갈까요?'**
  String get onbDistanceTitle;

  /// No description provided for @onbDistanceDesc.
  ///
  /// In ko, this message translates to:
  /// **'캠퍼스 기준으로 재요. 시간은 직선거리로 환산한 대략적인 값이에요.'**
  String get onbDistanceDesc;

  /// No description provided for @onbWalkMinutes.
  ///
  /// In ko, this message translates to:
  /// **'도보 {minutes}분'**
  String onbWalkMinutes(int minutes);

  /// No description provided for @onbDriveMinutes.
  ///
  /// In ko, this message translates to:
  /// **'차량 {minutes}분'**
  String onbDriveMinutes(int minutes);

  /// No description provided for @onbWalkLabel.
  ///
  /// In ko, this message translates to:
  /// **'도보'**
  String get onbWalkLabel;

  /// No description provided for @onbDriveLabel.
  ///
  /// In ko, this message translates to:
  /// **'차량'**
  String get onbDriveLabel;

  /// No description provided for @onbNeedDistance.
  ///
  /// In ko, this message translates to:
  /// **'거리를 골라주세요.'**
  String get onbNeedDistance;

  /// No description provided for @onbOriginTitle.
  ///
  /// In ko, this message translates to:
  /// **'기준 위치: 캠퍼스 중심'**
  String get onbOriginTitle;

  /// No description provided for @onbOriginHint.
  ///
  /// In ko, this message translates to:
  /// **'정문 좌표가 아직 없어서 캠퍼스 중심점에서 직선거리로 재요.'**
  String get onbOriginHint;

  /// No description provided for @onbCompanionTitle.
  ///
  /// In ko, this message translates to:
  /// **'누구와 먹나요?'**
  String get onbCompanionTitle;

  /// No description provided for @onbCompanionDesc.
  ///
  /// In ko, this message translates to:
  /// **'평소 누구와 식사하는지 골라주세요. 여러 개 선택할 수 있어요.'**
  String get onbCompanionDesc;

  /// No description provided for @companionSolo.
  ///
  /// In ko, this message translates to:
  /// **'혼자'**
  String get companionSolo;

  /// No description provided for @companionFriends.
  ///
  /// In ko, this message translates to:
  /// **'친구 2~3명'**
  String get companionFriends;

  /// No description provided for @companionGroup.
  ///
  /// In ko, this message translates to:
  /// **'4명 이상'**
  String get companionGroup;

  /// No description provided for @companionSenior.
  ///
  /// In ko, this message translates to:
  /// **'선배와'**
  String get companionSenior;

  /// No description provided for @companionJunior.
  ///
  /// In ko, this message translates to:
  /// **'후배와'**
  String get companionJunior;

  /// No description provided for @companionProfessor.
  ///
  /// In ko, this message translates to:
  /// **'교수님과'**
  String get companionProfessor;

  /// No description provided for @onbFoodTitle.
  ///
  /// In ko, this message translates to:
  /// **'끌리는 음식'**
  String get onbFoodTitle;

  /// No description provided for @onbFoodDesc.
  ///
  /// In ko, this message translates to:
  /// **'여러 개 골라도 돼요. 건너뛰어도 괜찮아요.'**
  String get onbFoodDesc;

  /// No description provided for @cuisineKorean.
  ///
  /// In ko, this message translates to:
  /// **'한식'**
  String get cuisineKorean;

  /// No description provided for @cuisineJapanese.
  ///
  /// In ko, this message translates to:
  /// **'일식'**
  String get cuisineJapanese;

  /// No description provided for @cuisineChinese.
  ///
  /// In ko, this message translates to:
  /// **'중식'**
  String get cuisineChinese;

  /// No description provided for @cuisineSnack.
  ///
  /// In ko, this message translates to:
  /// **'분식'**
  String get cuisineSnack;

  /// No description provided for @cuisineCafe.
  ///
  /// In ko, this message translates to:
  /// **'카페'**
  String get cuisineCafe;

  /// No description provided for @cuisineWestern.
  ///
  /// In ko, this message translates to:
  /// **'양식'**
  String get cuisineWestern;

  /// No description provided for @cuisineSalad.
  ///
  /// In ko, this message translates to:
  /// **'샐러드'**
  String get cuisineSalad;

  /// No description provided for @cuisineAny.
  ///
  /// In ko, this message translates to:
  /// **'상관없음'**
  String get cuisineAny;

  /// No description provided for @tagSpicy.
  ///
  /// In ko, this message translates to:
  /// **'매콤한'**
  String get tagSpicy;

  /// No description provided for @tagHearty.
  ///
  /// In ko, this message translates to:
  /// **'든든한'**
  String get tagHearty;

  /// No description provided for @tagValue.
  ///
  /// In ko, this message translates to:
  /// **'가성비'**
  String get tagValue;

  /// No description provided for @tagLight.
  ///
  /// In ko, this message translates to:
  /// **'가벼운'**
  String get tagLight;

  /// No description provided for @onbUntriedTitle.
  ///
  /// In ko, this message translates to:
  /// **'안 먹어 본 메뉴 먼저'**
  String get onbUntriedTitle;

  /// No description provided for @onbUntriedDesc.
  ///
  /// In ko, this message translates to:
  /// **'먹은 기록을 보고 최근에 먹은 종류는 뒤로 미뤄요. 기록 기능이 열리면 적용돼요.'**
  String get onbUntriedDesc;

  /// No description provided for @onbFilterNote.
  ///
  /// In ko, this message translates to:
  /// **'지금은 거리와 음식 종류만 결과에 반영돼요. 예산·함께 먹는 사람·취향 태그는 가격·좌석 정보가 생기면 적용할 수 있도록 저장만 해둬요.'**
  String get onbFilterNote;

  /// No description provided for @onbCountLabel.
  ///
  /// In ko, this message translates to:
  /// **'지금 조건이면 {count}곳'**
  String onbCountLabel(int count);

  /// No description provided for @onbCountUnknown.
  ///
  /// In ko, this message translates to:
  /// **'주변 맛집을 불러오는 중이에요'**
  String get onbCountUnknown;

  /// No description provided for @onbCountNote.
  ///
  /// In ko, this message translates to:
  /// **'거리·음식 종류만 반영'**
  String get onbCountNote;

  /// No description provided for @onbClearAll.
  ///
  /// In ko, this message translates to:
  /// **'선택 모두 지우기'**
  String get onbClearAll;

  /// No description provided for @onbRandom.
  ///
  /// In ko, this message translates to:
  /// **'랜덤'**
  String get onbRandom;

  /// No description provided for @onbViewRecs.
  ///
  /// In ko, this message translates to:
  /// **'추천 보기'**
  String get onbViewRecs;

  /// No description provided for @onbViewRecsCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}곳 추천 보기'**
  String onbViewRecsCount(int count);

  /// No description provided for @onbSave.
  ///
  /// In ko, this message translates to:
  /// **'저장하기'**
  String get onbSave;

  /// No description provided for @onbRandomNone.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 맛집이 없어요.'**
  String get onbRandomNone;

  /// No description provided for @onbLogout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get onbLogout;

  /// No description provided for @prefsEditTitle.
  ///
  /// In ko, this message translates to:
  /// **'나의 취향 설정'**
  String get prefsEditTitle;

  /// No description provided for @prefsEditSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'저장한 조건을 바꿀 수 있어요.'**
  String get prefsEditSubtitle;

  /// No description provided for @prefsSaved.
  ///
  /// In ko, this message translates to:
  /// **'취향을 저장했어요.'**
  String get prefsSaved;

  /// No description provided for @prefsLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장된 취향을 불러오지 못했어요'**
  String get prefsLoadFailed;

  /// No description provided for @prefsSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했어요. 선택한 내용은 그대로 있으니 다시 시도해주세요.'**
  String get prefsSaveFailed;

  /// No description provided for @homeTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 뭐 먹지?'**
  String get homeTitle;

  /// No description provided for @homeSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'{part} · {time} · {origin} 출발 기준'**
  String homeSubtitle(String part, String time, String origin);

  /// No description provided for @dayPartBreakfast.
  ///
  /// In ko, this message translates to:
  /// **'아침'**
  String get dayPartBreakfast;

  /// No description provided for @dayPartLunch.
  ///
  /// In ko, this message translates to:
  /// **'점심'**
  String get dayPartLunch;

  /// No description provided for @dayPartDinner.
  ///
  /// In ko, this message translates to:
  /// **'저녁'**
  String get dayPartDinner;

  /// No description provided for @dayPartLateNight.
  ///
  /// In ko, this message translates to:
  /// **'야식'**
  String get dayPartLateNight;

  /// No description provided for @homeRestartTooltip.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시'**
  String get homeRestartTooltip;

  /// No description provided for @homeProfileTooltip.
  ///
  /// In ko, this message translates to:
  /// **'프로필'**
  String get homeProfileTooltip;

  /// No description provided for @homeOriginChip.
  ///
  /// In ko, this message translates to:
  /// **'{origin} 기준'**
  String homeOriginChip(String origin);

  /// No description provided for @homeConditionsChip.
  ///
  /// In ko, this message translates to:
  /// **'조건'**
  String get homeConditionsChip;

  /// No description provided for @homeConditionsActive.
  ///
  /// In ko, this message translates to:
  /// **'조건 {count}개 적용 중'**
  String homeConditionsActive(int count);

  /// No description provided for @homeHeroRank.
  ///
  /// In ko, this message translates to:
  /// **'{total}곳 중 {rank}순위'**
  String homeHeroRank(int total, int rank);

  /// No description provided for @homePriceFrom.
  ///
  /// In ko, this message translates to:
  /// **'{price}~'**
  String homePriceFrom(int price);

  /// No description provided for @homeMetaReviews.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 {count}'**
  String homeMetaReviews(int count);

  /// No description provided for @homeReasonCuisine.
  ///
  /// In ko, this message translates to:
  /// **'{cuisine}, 고른 음식이에요'**
  String homeReasonCuisine(String cuisine);

  /// No description provided for @homeReasonBudget.
  ///
  /// In ko, this message translates to:
  /// **'예산 안이에요'**
  String get homeReasonBudget;

  /// No description provided for @homeReasonClosest.
  ///
  /// In ko, this message translates to:
  /// **'가장 가까워요'**
  String get homeReasonClosest;

  /// No description provided for @homeReasonWalk.
  ///
  /// In ko, this message translates to:
  /// **'걸어서 {minutes}분이에요'**
  String homeReasonWalk(int minutes);

  /// No description provided for @homeArrival.
  ///
  /// In ko, this message translates to:
  /// **'도착 예상'**
  String get homeArrival;

  /// No description provided for @homeLastOrder.
  ///
  /// In ko, this message translates to:
  /// **'주문 마감'**
  String get homeLastOrder;

  /// No description provided for @homeWalkAbout.
  ///
  /// In ko, this message translates to:
  /// **'도보 약 {minutes}분'**
  String homeWalkAbout(int minutes);

  /// No description provided for @homeSlackHM.
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간 {minutes}분 여유'**
  String homeSlackHM(int hours, int minutes);

  /// No description provided for @homeSlackH.
  ///
  /// In ko, this message translates to:
  /// **'{hours}시간 여유'**
  String homeSlackH(int hours);

  /// No description provided for @homeSlackM.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분 여유'**
  String homeSlackM(int minutes);

  /// No description provided for @homeNoInfo.
  ///
  /// In ko, this message translates to:
  /// **'정보 없음'**
  String get homeNoInfo;

  /// No description provided for @homeClosesBeforeArrival.
  ///
  /// In ko, this message translates to:
  /// **'도착 전에 마감돼요'**
  String get homeClosesBeforeArrival;

  /// No description provided for @homeDirections.
  ///
  /// In ko, this message translates to:
  /// **'길찾기'**
  String get homeDirections;

  /// No description provided for @homeInfo.
  ///
  /// In ko, this message translates to:
  /// **'정보'**
  String get homeInfo;

  /// No description provided for @homeAltTitle.
  ///
  /// In ko, this message translates to:
  /// **'마음에 안 들면'**
  String get homeAltTitle;

  /// No description provided for @homePickForMe.
  ///
  /// In ko, this message translates to:
  /// **'하나 골라줘'**
  String get homePickForMe;

  /// No description provided for @homeRestart.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시'**
  String get homeRestart;

  /// No description provided for @homePromptTitle.
  ///
  /// In ko, this message translates to:
  /// **'조건을 고르고 추천받아 보세요'**
  String get homePromptTitle;

  /// No description provided for @homePromptMessage.
  ///
  /// In ko, this message translates to:
  /// **'예산·거리 같은 조건을 정하거나 ‘오늘의 추천 받기’를 눌러 보세요.'**
  String get homePromptMessage;

  /// No description provided for @homeGameButton.
  ///
  /// In ko, this message translates to:
  /// **'게임으로 정하기'**
  String get homeGameButton;

  /// No description provided for @homeGameTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 뭐 먹지? 게임으로!'**
  String get homeGameTitle;

  /// No description provided for @homeGameSub.
  ///
  /// In ko, this message translates to:
  /// **'지금 조건에 맞는 곳 중에서 골라요.'**
  String get homeGameSub;

  /// No description provided for @homeGameRoulette.
  ///
  /// In ko, this message translates to:
  /// **'룰렛'**
  String get homeGameRoulette;

  /// No description provided for @homeGameRouletteHint.
  ///
  /// In ko, this message translates to:
  /// **'돌려서 멈춘 곳으로'**
  String get homeGameRouletteHint;

  /// No description provided for @homeGameLadder.
  ///
  /// In ko, this message translates to:
  /// **'사다리타기'**
  String get homeGameLadder;

  /// No description provided for @homeGameLadderHint.
  ///
  /// In ko, this message translates to:
  /// **'한 줄을 골라 내려가요'**
  String get homeGameLadderHint;

  /// No description provided for @homeGameCards.
  ///
  /// In ko, this message translates to:
  /// **'카드 뽑기'**
  String get homeGameCards;

  /// No description provided for @homeGameCardsHint.
  ///
  /// In ko, this message translates to:
  /// **'뒤집어서 나온 곳으로'**
  String get homeGameCardsHint;

  /// No description provided for @homeGameSpin.
  ///
  /// In ko, this message translates to:
  /// **'돌리기!'**
  String get homeGameSpin;

  /// No description provided for @homeGameSpinning.
  ///
  /// In ko, this message translates to:
  /// **'돌아가는 중…'**
  String get homeGameSpinning;

  /// No description provided for @homeGameLadderPrompt.
  ///
  /// In ko, this message translates to:
  /// **'출발할 줄을 골라요'**
  String get homeGameLadderPrompt;

  /// No description provided for @homeGameCardsPrompt.
  ///
  /// In ko, this message translates to:
  /// **'카드를 한 장 골라요'**
  String get homeGameCardsPrompt;

  /// No description provided for @homeGameResult.
  ///
  /// In ko, this message translates to:
  /// **'오늘은 여기!'**
  String get homeGameResult;

  /// No description provided for @homeGameAgain.
  ///
  /// In ko, this message translates to:
  /// **'다시 하기'**
  String get homeGameAgain;

  /// No description provided for @homeGameConfirm.
  ///
  /// In ko, this message translates to:
  /// **'여기로 정하기'**
  String get homeGameConfirm;

  /// No description provided for @homeGameBack.
  ///
  /// In ko, this message translates to:
  /// **'다른 게임'**
  String get homeGameBack;

  /// No description provided for @homeGameChosen.
  ///
  /// In ko, this message translates to:
  /// **'{name}(으)로 정했어요. 맨 위 추천 카드에서 확인하세요.'**
  String homeGameChosen(String name);

  /// No description provided for @homeCmpCloser.
  ///
  /// In ko, this message translates to:
  /// **'{minutes}분 더 가까워요'**
  String homeCmpCloser(int minutes);

  /// No description provided for @homeCmpCheaper.
  ///
  /// In ko, this message translates to:
  /// **'{amount}원 더 싸요'**
  String homeCmpCheaper(int amount);

  /// No description provided for @homeCmpRating.
  ///
  /// In ko, this message translates to:
  /// **'평점이 더 높아요'**
  String get homeCmpRating;

  /// No description provided for @homeCmpLater.
  ///
  /// In ko, this message translates to:
  /// **'더 늦게까지 열어요'**
  String get homeCmpLater;

  /// No description provided for @homeStatusOrderable.
  ///
  /// In ko, this message translates to:
  /// **'주문 가능'**
  String get homeStatusOrderable;

  /// No description provided for @homeStatusClosesAt.
  ///
  /// In ko, this message translates to:
  /// **'주문 마감 {time}'**
  String homeStatusClosesAt(String time);

  /// No description provided for @homeSeeOnMap.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 {count}곳 지도에서 보기'**
  String homeSeeOnMap(int count);

  /// No description provided for @homeEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 곳이 없어요'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyMessage.
  ///
  /// In ko, this message translates to:
  /// **'조건을 조금 풀면 더 많이 보여요.'**
  String get homeEmptyMessage;

  /// No description provided for @homeMealTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 학식'**
  String get homeMealTitle;

  /// No description provided for @homeMealChipNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 {meal}'**
  String homeMealChipNow(String meal);

  /// No description provided for @homeMealChipToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘 {meal}'**
  String homeMealChipToday(String meal);

  /// No description provided for @homeMealChipTomorrow.
  ///
  /// In ko, this message translates to:
  /// **'내일 {meal}'**
  String homeMealChipTomorrow(String meal);

  /// No description provided for @homeMealNone.
  ///
  /// In ko, this message translates to:
  /// **'곧 먹을 수 있는 학식 메뉴가 아직 등록되지 않았어요.'**
  String get homeMealNone;

  /// No description provided for @homeMealAvgCaption.
  ///
  /// In ko, this message translates to:
  /// **'점심 한 끼 평균 · {place}에서 도보 15분 안 식당 기준'**
  String homeMealAvgCaption(String place);

  /// No description provided for @homeMealBarCafeteria.
  ///
  /// In ko, this message translates to:
  /// **'학식'**
  String get homeMealBarCafeteria;

  /// No description provided for @homeMealBarOutside.
  ///
  /// In ko, this message translates to:
  /// **'바깥 식당'**
  String get homeMealBarOutside;

  /// No description provided for @homeMealSavingPre.
  ///
  /// In ko, this message translates to:
  /// **'한 달 20끼를 학식으로 먹으면 '**
  String get homeMealSavingPre;

  /// No description provided for @homeMealSavingPost.
  ///
  /// In ko, this message translates to:
  /// **' 아껴요'**
  String get homeMealSavingPost;

  /// No description provided for @homeMealNoCompare.
  ///
  /// In ko, this message translates to:
  /// **'비교할 가격 정보가 아직 부족해요. 학식과 바깥 식당 가격이 모두 있어야 비교할 수 있어요.'**
  String get homeMealNoCompare;

  /// No description provided for @homeMealWeekly.
  ///
  /// In ko, this message translates to:
  /// **'이번 주 식단'**
  String get homeMealWeekly;

  /// No description provided for @homeMealCompare.
  ///
  /// In ko, this message translates to:
  /// **'바깥 식당과 비교'**
  String get homeMealCompare;

  /// No description provided for @homeCompareSoon.
  ///
  /// In ko, this message translates to:
  /// **'가격 비교 화면은 준비 중이에요.'**
  String get homeCompareSoon;

  /// No description provided for @originCampusCenter.
  ///
  /// In ko, this message translates to:
  /// **'캠퍼스 중심'**
  String get originCampusCenter;

  /// No description provided for @originSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'어디서 출발하나요?'**
  String get originSheetTitle;

  /// No description provided for @originSheetDesc.
  ///
  /// In ko, this message translates to:
  /// **'고른 위치에서 걷는 거리로 지도와 추천을 다시 정렬해요. 건물 위치는 시연용 예시예요.'**
  String get originSheetDesc;

  /// No description provided for @originGroupGates.
  ///
  /// In ko, this message translates to:
  /// **'출입문'**
  String get originGroupGates;

  /// No description provided for @originGroupColleges.
  ///
  /// In ko, this message translates to:
  /// **'단과대학'**
  String get originGroupColleges;

  /// No description provided for @originGroupBuildings.
  ///
  /// In ko, this message translates to:
  /// **'주요 건물'**
  String get originGroupBuildings;

  /// No description provided for @originGroupPins.
  ///
  /// In ko, this message translates to:
  /// **'내 핀'**
  String get originGroupPins;

  /// No description provided for @originNoPins.
  ///
  /// In ko, this message translates to:
  /// **'아직 저장한 핀이 없어요.'**
  String get originNoPins;

  /// No description provided for @originNearest.
  ///
  /// In ko, this message translates to:
  /// **'가장 가까운 곳: {name} · 도보 {minutes}분'**
  String originNearest(String name, int minutes);

  /// No description provided for @originNearestNone.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 가까운 식당이 없어요'**
  String get originNearestNone;

  /// No description provided for @originPickOnMap.
  ///
  /// In ko, this message translates to:
  /// **'지도에서 직접 찍기'**
  String get originPickOnMap;

  /// No description provided for @originPinPickerTitle.
  ///
  /// In ko, this message translates to:
  /// **'출발 위치 정하기'**
  String get originPinPickerTitle;

  /// No description provided for @originPinPickerHint.
  ///
  /// In ko, this message translates to:
  /// **'지도를 움직여 핀을 원하는 곳에 맞춰주세요.'**
  String get originPinPickerHint;

  /// No description provided for @originPinConfirm.
  ///
  /// In ko, this message translates to:
  /// **'여기로 정하기'**
  String get originPinConfirm;

  /// No description provided for @originPinNameTitle.
  ///
  /// In ko, this message translates to:
  /// **'핀 이름'**
  String get originPinNameTitle;

  /// No description provided for @originPinNameHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 기숙사 앞'**
  String get originPinNameHint;

  /// No description provided for @originPinDefaultName.
  ///
  /// In ko, this message translates to:
  /// **'내 핀 {number}'**
  String originPinDefaultName(int number);

  /// No description provided for @originPinDelete.
  ///
  /// In ko, this message translates to:
  /// **'핀 삭제'**
  String get originPinDelete;

  /// No description provided for @originPinFailed.
  ///
  /// In ko, this message translates to:
  /// **'위치를 가져오지 못했어요. 다시 시도해주세요.'**
  String get originPinFailed;

  /// No description provided for @condTitle.
  ///
  /// In ko, this message translates to:
  /// **'조건'**
  String get condTitle;

  /// No description provided for @condSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'홈·지도·검색에 똑같이 적용돼요.'**
  String get condSubtitle;

  /// No description provided for @condMust.
  ///
  /// In ko, this message translates to:
  /// **'꼭 지킬 조건'**
  String get condMust;

  /// No description provided for @condMustHint.
  ///
  /// In ko, this message translates to:
  /// **'넘는 식당은 빼요'**
  String get condMustHint;

  /// No description provided for @condMissingNote.
  ///
  /// In ko, this message translates to:
  /// **'가격·영업 정보가 없는 식당은 빼지 않고 그대로 보여드려요.'**
  String get condMissingNote;

  /// No description provided for @condChange.
  ///
  /// In ko, this message translates to:
  /// **'바꾸기'**
  String get condChange;

  /// No description provided for @condOpenNow.
  ///
  /// In ko, this message translates to:
  /// **'지금 주문 가능한 곳만'**
  String get condOpenNow;

  /// No description provided for @condOpenNowHint.
  ///
  /// In ko, this message translates to:
  /// **'도착 예상 시각에 주문이 마감되지 않은 곳이에요. 나중에 갈 곳을 찾을 때만 꺼 주세요.'**
  String get condOpenNowHint;

  /// No description provided for @condCuisine.
  ///
  /// In ko, this message translates to:
  /// **'음식 종류'**
  String get condCuisine;

  /// No description provided for @condOps.
  ///
  /// In ko, this message translates to:
  /// **'운영·편의'**
  String get condOps;

  /// No description provided for @condAmenityNoBreak.
  ///
  /// In ko, this message translates to:
  /// **'브레이크타임 없음'**
  String get condAmenityNoBreak;

  /// No description provided for @condAmenityParking.
  ///
  /// In ko, this message translates to:
  /// **'주차 가능'**
  String get condAmenityParking;

  /// No description provided for @condAmenityLocalCurrency.
  ///
  /// In ko, this message translates to:
  /// **'지역화폐(아산페이)'**
  String get condAmenityLocalCurrency;

  /// No description provided for @condAmenityFast.
  ///
  /// In ko, this message translates to:
  /// **'빠른 회전'**
  String get condAmenityFast;

  /// No description provided for @condAmenityTakeout.
  ///
  /// In ko, this message translates to:
  /// **'포장 가능'**
  String get condAmenityTakeout;

  /// No description provided for @condAmenityLate.
  ///
  /// In ko, this message translates to:
  /// **'밤 10시까지'**
  String get condAmenityLate;

  /// No description provided for @condSoft.
  ///
  /// In ko, this message translates to:
  /// **'추천 순서에 반영'**
  String get condSoft;

  /// No description provided for @condParty.
  ///
  /// In ko, this message translates to:
  /// **'몇 명이 먹나요?'**
  String get condParty;

  /// No description provided for @condPartyFew.
  ///
  /// In ko, this message translates to:
  /// **'2~3명'**
  String get condPartyFew;

  /// No description provided for @condNeeds.
  ///
  /// In ko, this message translates to:
  /// **'필요한 것'**
  String get condNeeds;

  /// No description provided for @condNeedQuiet.
  ///
  /// In ko, this message translates to:
  /// **'조용한 대화'**
  String get condNeedQuiet;

  /// No description provided for @condNeedQuick.
  ///
  /// In ko, this message translates to:
  /// **'빠른 식사'**
  String get condNeedQuick;

  /// No description provided for @condNeedGenerous.
  ///
  /// In ko, this message translates to:
  /// **'넉넉한 양'**
  String get condNeedGenerous;

  /// No description provided for @condUntried.
  ///
  /// In ko, this message translates to:
  /// **'안 가 본 식당 먼저'**
  String get condUntried;

  /// No description provided for @condUntriedHint.
  ///
  /// In ko, this message translates to:
  /// **'먹은 기록 {count}개 반영 · 식당 단위로 봐요'**
  String condUntriedHint(int count);

  /// No description provided for @condSort.
  ///
  /// In ko, this message translates to:
  /// **'정렬'**
  String get condSort;

  /// No description provided for @condSortRecommended.
  ///
  /// In ko, this message translates to:
  /// **'추천순'**
  String get condSortRecommended;

  /// No description provided for @condSortPrice.
  ///
  /// In ko, this message translates to:
  /// **'가격순'**
  String get condSortPrice;

  /// No description provided for @condSortRating.
  ///
  /// In ko, this message translates to:
  /// **'평점순'**
  String get condSortRating;

  /// No description provided for @condSoftNote.
  ///
  /// In ko, this message translates to:
  /// **'지금은 가까운 순으로 추천해요. 함께 먹는 사람·필요한 것은 데이터가 생기면 순서에 반영돼요.'**
  String get condSoftNote;

  /// No description provided for @condResetAll.
  ///
  /// In ko, this message translates to:
  /// **'모두 풀기'**
  String get condResetAll;

  /// No description provided for @condResetThis.
  ///
  /// In ko, this message translates to:
  /// **'이 설정만 풀기'**
  String get condResetThis;

  /// No description provided for @condShowCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}곳 보기'**
  String condShowCount(int count);

  /// No description provided for @condNoMatch.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 곳이 없어요'**
  String get condNoMatch;

  /// No description provided for @condRestart.
  ///
  /// In ko, this message translates to:
  /// **'처음 화면으로 돌아가 다시 설정'**
  String get condRestart;

  /// No description provided for @condRestartTitle.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시 설정할까요?'**
  String get condRestartTitle;

  /// No description provided for @condRestartBody.
  ///
  /// In ko, this message translates to:
  /// **'지금 조건과 출발 위치를 처음 상태로 되돌리고, 취향 설정을 다시 시작해요.'**
  String get condRestartBody;

  /// No description provided for @condRestartAction.
  ///
  /// In ko, this message translates to:
  /// **'다시 설정'**
  String get condRestartAction;

  /// No description provided for @condRestartGuestDone.
  ///
  /// In ko, this message translates to:
  /// **'조건과 출발 위치를 처음 상태로 되돌렸어요.'**
  String get condRestartGuestDone;

  /// No description provided for @restaurantAboutTitle.
  ///
  /// In ko, this message translates to:
  /// **'소개'**
  String get restaurantAboutTitle;

  /// No description provided for @restaurantMenuTitle.
  ///
  /// In ko, this message translates to:
  /// **'메뉴'**
  String get restaurantMenuTitle;

  /// No description provided for @restaurantMenuSoldOut.
  ///
  /// In ko, this message translates to:
  /// **'품절'**
  String get restaurantMenuSoldOut;

  /// No description provided for @restaurantGalleryTitle.
  ///
  /// In ko, this message translates to:
  /// **'사진'**
  String get restaurantGalleryTitle;

  /// No description provided for @restaurantMenuRecommended.
  ///
  /// In ko, this message translates to:
  /// **'추천'**
  String get restaurantMenuRecommended;

  /// No description provided for @restaurantPriceWon.
  ///
  /// In ko, this message translates to:
  /// **'{price}원'**
  String restaurantPriceWon(int price);

  /// No description provided for @mealBreakfastProgram.
  ///
  /// In ko, this message translates to:
  /// **'조식 · 천원의 아침밥'**
  String get mealBreakfastProgram;

  /// No description provided for @mealHeading.
  ///
  /// In ko, this message translates to:
  /// **'{day} {meal} 학식'**
  String mealHeading(String day, String meal);

  /// No description provided for @mealDayTomorrow.
  ///
  /// In ko, this message translates to:
  /// **'내일'**
  String get mealDayTomorrow;

  /// No description provided for @myTitle.
  ///
  /// In ko, this message translates to:
  /// **'마이페이지'**
  String get myTitle;

  /// No description provided for @myConditionsTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 조건'**
  String get myConditionsTitle;

  /// No description provided for @myConditionsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 고른 조건이 없어요. 예산과 거리부터 골라 보세요.'**
  String get myConditionsEmpty;

  /// No description provided for @myRestart.
  ///
  /// In ko, this message translates to:
  /// **'처음부터 다시 설정'**
  String get myRestart;

  /// No description provided for @myOriginHint.
  ///
  /// In ko, this message translates to:
  /// **'거리 계산 기준 위치 · 저장한 핀 {count}개'**
  String myOriginHint(int count);

  /// No description provided for @myActivityTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 활동'**
  String get myActivityTitle;

  /// No description provided for @recordsPageTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 기록'**
  String get recordsPageTitle;

  /// No description provided for @recordsSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'나만 볼 수 있는 맛집 일기예요'**
  String get recordsSubtitle;

  /// No description provided for @recordsAdd.
  ///
  /// In ko, this message translates to:
  /// **'기록하기'**
  String get recordsAdd;

  /// No description provided for @recordsReportTitle.
  ///
  /// In ko, this message translates to:
  /// **'{month}월 리포트'**
  String recordsReportTitle(int month);

  /// No description provided for @recordsReportBasis.
  ///
  /// In ko, this message translates to:
  /// **'이번 달 기록 기준'**
  String get recordsReportBasis;

  /// No description provided for @recordsStatMeals.
  ///
  /// In ko, this message translates to:
  /// **'외식'**
  String get recordsStatMeals;

  /// No description provided for @recordsStatSpend.
  ///
  /// In ko, this message translates to:
  /// **'식비 합계'**
  String get recordsStatSpend;

  /// No description provided for @recordsStatAvg.
  ///
  /// In ko, this message translates to:
  /// **'한 끼 평균'**
  String get recordsStatAvg;

  /// No description provided for @recordsReportHint.
  ///
  /// In ko, this message translates to:
  /// **'먹은 곳을 남기면 이번 달 식비와 단골집을 정리해 드려요.'**
  String get recordsReportHint;

  /// No description provided for @recordsTabEaten.
  ///
  /// In ko, this message translates to:
  /// **'먹은 기록 {count}'**
  String recordsTabEaten(String count);

  /// No description provided for @recordsTabWant.
  ///
  /// In ko, this message translates to:
  /// **'가고 싶은 곳 {count}'**
  String recordsTabWant(String count);

  /// No description provided for @recordsNoRecordsTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 남긴 기록이 없어요'**
  String get recordsNoRecordsTitle;

  /// No description provided for @recordsNoRecordsBody.
  ///
  /// In ko, this message translates to:
  /// **'먹은 곳·메뉴·금액·함께한 사람을 남기면 나만의 맛집 일기가 돼요.'**
  String get recordsNoRecordsBody;

  /// No description provided for @recordsFirst.
  ///
  /// In ko, this message translates to:
  /// **'첫 기록 남기기'**
  String get recordsFirst;

  /// No description provided for @communitySubtitle.
  ///
  /// In ko, this message translates to:
  /// **'{campus} 학생 커뮤니티'**
  String communitySubtitle(String campus);

  /// No description provided for @communityMyActivity.
  ///
  /// In ko, this message translates to:
  /// **'내 활동'**
  String get communityMyActivity;

  /// No description provided for @communityFilterAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get communityFilterAll;

  /// No description provided for @communityFilterReviews.
  ///
  /// In ko, this message translates to:
  /// **'맛집 리뷰'**
  String get communityFilterReviews;

  /// No description provided for @communityFilterMeets.
  ///
  /// In ko, this message translates to:
  /// **'같이 먹어요'**
  String get communityFilterMeets;

  /// No description provided for @communityFilterQuestions.
  ///
  /// In ko, this message translates to:
  /// **'질문'**
  String get communityFilterQuestions;

  /// No description provided for @communityComposerTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘 먹은 메뉴를 나눠볼까요?'**
  String get communityComposerTitle;

  /// No description provided for @communityWriteReview.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 쓰기'**
  String get communityWriteReview;

  /// No description provided for @communityStartMeet.
  ///
  /// In ko, this message translates to:
  /// **'같이 먹기 모집'**
  String get communityStartMeet;

  /// No description provided for @communityAsk.
  ///
  /// In ko, this message translates to:
  /// **'질문 남기기'**
  String get communityAsk;

  /// No description provided for @communityFeedTitle.
  ///
  /// In ko, this message translates to:
  /// **'학교 근처 이야기'**
  String get communityFeedTitle;

  /// No description provided for @communitySortLatest.
  ///
  /// In ko, this message translates to:
  /// **'최신순'**
  String get communitySortLatest;

  /// No description provided for @communityEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 올라온 이야기가 없어요'**
  String get communityEmptyTitle;

  /// No description provided for @communityEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'오늘 먹은 메뉴나 같이 먹을 사람을 첫 글로 올려 보세요.'**
  String get communityEmptyBody;

  /// No description provided for @communityComposeSoon.
  ///
  /// In ko, this message translates to:
  /// **'밥수다 글쓰기는 준비 중이에요.'**
  String get communityComposeSoon;

  /// No description provided for @mapPageTitle.
  ///
  /// In ko, this message translates to:
  /// **'주변 맛집'**
  String get mapPageTitle;

  /// No description provided for @mapOpenNowChip.
  ///
  /// In ko, this message translates to:
  /// **'지금 주문 가능'**
  String get mapOpenNowChip;

  /// No description provided for @mapMatchCount.
  ///
  /// In ko, this message translates to:
  /// **'조건에 맞는 {count}곳'**
  String mapMatchCount(int count);

  /// No description provided for @mapSortHint.
  ///
  /// In ko, this message translates to:
  /// **'{origin} 기준 · 이동 시간은 직선거리로 추정한 값이에요'**
  String mapSortHint(String origin);

  /// No description provided for @mapRecenter.
  ///
  /// In ko, this message translates to:
  /// **'기준 위치로 이동'**
  String get mapRecenter;

  /// No description provided for @profileAvatarEdit.
  ///
  /// In ko, this message translates to:
  /// **'꾸미기'**
  String get profileAvatarEdit;

  /// No description provided for @profileAvatarSheetTitle.
  ///
  /// In ko, this message translates to:
  /// **'프로필 이미지 선택'**
  String get profileAvatarSheetTitle;

  /// No description provided for @profileAvatarSheetSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'마스코트에서 선택'**
  String get profileAvatarSheetSubtitle;

  /// No description provided for @profileAvatarConfirm.
  ///
  /// In ko, this message translates to:
  /// **'선택 완료'**
  String get profileAvatarConfirm;

  /// No description provided for @profileAvatarSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'프로필 이미지를 저장하지 못했어요. 다시 시도해주세요.'**
  String get profileAvatarSaveFailed;

  /// No description provided for @profileAvatarOption.
  ///
  /// In ko, this message translates to:
  /// **'마스코트 {n}'**
  String profileAvatarOption(int n);

  /// No description provided for @profileAvatarChange.
  ///
  /// In ko, this message translates to:
  /// **'프로필 이미지 바꾸기'**
  String get profileAvatarChange;

  /// No description provided for @homeSearchFieldHint.
  ///
  /// In ko, this message translates to:
  /// **'식당, 메뉴, 카테고리 검색'**
  String get homeSearchFieldHint;

  /// No description provided for @homeRecommendButton.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 추천 받기'**
  String get homeRecommendButton;

  /// No description provided for @homeTodayPicksTitle.
  ///
  /// In ko, this message translates to:
  /// **'오늘의 추천'**
  String get homeTodayPicksTitle;

  /// No description provided for @homeFilterBudget.
  ///
  /// In ko, this message translates to:
  /// **'예산'**
  String get homeFilterBudget;

  /// No description provided for @homeFilterDistance.
  ///
  /// In ko, this message translates to:
  /// **'거리'**
  String get homeFilterDistance;

  /// No description provided for @homeFilterParty.
  ///
  /// In ko, this message translates to:
  /// **'인원'**
  String get homeFilterParty;

  /// No description provided for @homeFilterPurpose.
  ///
  /// In ko, this message translates to:
  /// **'목적'**
  String get homeFilterPurpose;

  /// No description provided for @homeFilterSort.
  ///
  /// In ko, this message translates to:
  /// **'정렬'**
  String get homeFilterSort;

  /// No description provided for @navMissions.
  ///
  /// In ko, this message translates to:
  /// **'미션'**
  String get navMissions;

  /// No description provided for @missionPageTitle.
  ///
  /// In ko, this message translates to:
  /// **'미션'**
  String get missionPageTitle;

  /// No description provided for @missionTabMonthlyFallback.
  ///
  /// In ko, this message translates to:
  /// **'이달의 미션'**
  String get missionTabMonthlyFallback;

  /// No description provided for @missionTabDaily.
  ///
  /// In ko, this message translates to:
  /// **'데일리'**
  String get missionTabDaily;

  /// No description provided for @missionTabWeekly.
  ///
  /// In ko, this message translates to:
  /// **'주간'**
  String get missionTabWeekly;

  /// No description provided for @missionTabChallenge.
  ///
  /// In ko, this message translates to:
  /// **'도전과제'**
  String get missionTabChallenge;

  /// No description provided for @missionCompletedLabel.
  ///
  /// In ko, this message translates to:
  /// **'완료한 미션'**
  String get missionCompletedLabel;

  /// No description provided for @missionProgressLabel.
  ///
  /// In ko, this message translates to:
  /// **'이번 달 진행률'**
  String get missionProgressLabel;

  /// No description provided for @missionPointsMonth.
  ///
  /// In ko, this message translates to:
  /// **'이번 달 획득 포인트'**
  String get missionPointsMonth;

  /// No description provided for @missionBadgePreview.
  ///
  /// In ko, this message translates to:
  /// **'이달의 뱃지'**
  String get missionBadgePreview;

  /// No description provided for @missionBadgeLockedHint.
  ///
  /// In ko, this message translates to:
  /// **'미션 {count}개를 완료하면 받을 수 있어요'**
  String missionBadgeLockedHint(int count);

  /// No description provided for @missionBadgeUnlocked.
  ///
  /// In ko, this message translates to:
  /// **'획득 완료'**
  String get missionBadgeUnlocked;

  /// No description provided for @missionDone.
  ///
  /// In ko, this message translates to:
  /// **'완료'**
  String get missionDone;

  /// No description provided for @missionBadgeReward.
  ///
  /// In ko, this message translates to:
  /// **'한정 뱃지'**
  String get missionBadgeReward;

  /// No description provided for @missionExpired.
  ///
  /// In ko, this message translates to:
  /// **'기간 종료'**
  String get missionExpired;

  /// No description provided for @missionUpcoming.
  ///
  /// In ko, this message translates to:
  /// **'예정'**
  String get missionUpcoming;

  /// No description provided for @missionDetailRequirement.
  ///
  /// In ko, this message translates to:
  /// **'완료 조건'**
  String get missionDetailRequirement;

  /// No description provided for @missionDetailProgress.
  ///
  /// In ko, this message translates to:
  /// **'진행 상황'**
  String get missionDetailProgress;

  /// No description provided for @missionDetailReward.
  ///
  /// In ko, this message translates to:
  /// **'보상'**
  String get missionDetailReward;

  /// No description provided for @missionDetailPeriod.
  ///
  /// In ko, this message translates to:
  /// **'기간'**
  String get missionDetailPeriod;

  /// No description provided for @missionResetsDaily.
  ///
  /// In ko, this message translates to:
  /// **'매일 0시(한국 시간)에 새로 시작돼요'**
  String get missionResetsDaily;

  /// No description provided for @missionResetsWeekly.
  ///
  /// In ko, this message translates to:
  /// **'매주 월요일 0시(한국 시간)에 새로 시작돼요'**
  String get missionResetsWeekly;

  /// No description provided for @missionUntil.
  ///
  /// In ko, this message translates to:
  /// **'{date}까지'**
  String missionUntil(String date);

  /// No description provided for @missionAlwaysOn.
  ///
  /// In ko, this message translates to:
  /// **'상시 진행'**
  String get missionAlwaysOn;

  /// No description provided for @missionActionRecommend.
  ///
  /// In ko, this message translates to:
  /// **'추천 받기'**
  String get missionActionRecommend;

  /// No description provided for @missionActionMap.
  ///
  /// In ko, this message translates to:
  /// **'맛집 찾으러 가기'**
  String get missionActionMap;

  /// No description provided for @missionActionFavorites.
  ///
  /// In ko, this message translates to:
  /// **'저렴한 맛집 찾기'**
  String get missionActionFavorites;

  /// No description provided for @missionActionCategories.
  ///
  /// In ko, this message translates to:
  /// **'카테고리 둘러보기'**
  String get missionActionCategories;

  /// No description provided for @missionActionReview.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 작성하기'**
  String get missionActionReview;

  /// No description provided for @missionActionPhoto.
  ///
  /// In ko, this message translates to:
  /// **'메뉴 사진 올리기'**
  String get missionActionPhoto;

  /// No description provided for @missionActionCorrect.
  ///
  /// In ko, this message translates to:
  /// **'정보 수정 제안하기'**
  String get missionActionCorrect;

  /// No description provided for @missionActionSoon.
  ///
  /// In ko, this message translates to:
  /// **'이 기능은 아직 준비 중이에요. 열리면 미션에 바로 반영돼요.'**
  String get missionActionSoon;

  /// No description provided for @missionCelebrationTitle.
  ///
  /// In ko, this message translates to:
  /// **'미션 완료!'**
  String get missionCelebrationTitle;

  /// No description provided for @missionCelebrationPoints.
  ///
  /// In ko, this message translates to:
  /// **'+{points}P 획득'**
  String missionCelebrationPoints(int points);

  /// No description provided for @missionCelebrationBadge.
  ///
  /// In ko, this message translates to:
  /// **'뱃지를 얻었어요'**
  String get missionCelebrationBadge;

  /// No description provided for @missionGuestTitle.
  ///
  /// In ko, this message translates to:
  /// **'로그인하고 미션에 참여해요'**
  String get missionGuestTitle;

  /// No description provided for @missionGuestBody.
  ///
  /// In ko, this message translates to:
  /// **'맛집을 찜하고 둘러볼 때마다 진행 상황이 쌓여요. 포인트와 뱃지는 계정에 저장돼요.'**
  String get missionGuestBody;

  /// No description provided for @missionEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'진행 중인 미션이 없어요'**
  String get missionEmptyTitle;

  /// No description provided for @missionEmptyBody.
  ///
  /// In ko, this message translates to:
  /// **'새 미션이 열리면 여기에 나타나요.'**
  String get missionEmptyBody;

  /// No description provided for @missionLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'미션을 불러오지 못했어요'**
  String get missionLoadFailed;

  /// No description provided for @missionMyBadges.
  ///
  /// In ko, this message translates to:
  /// **'내 뱃지'**
  String get missionMyBadges;

  /// No description provided for @missionBadgesNone.
  ///
  /// In ko, this message translates to:
  /// **'아직 얻은 뱃지가 없어요. 미션을 완료해 보세요.'**
  String get missionBadgesNone;

  /// No description provided for @missionBadgesAll.
  ///
  /// In ko, this message translates to:
  /// **'전체 보기'**
  String get missionBadgesAll;

  /// No description provided for @missionBadgeCollectionTitle.
  ///
  /// In ko, this message translates to:
  /// **'뱃지 컬렉션'**
  String get missionBadgeCollectionTitle;

  /// No description provided for @missionTotalPoints.
  ///
  /// In ko, this message translates to:
  /// **'누적 포인트'**
  String get missionTotalPoints;

  /// No description provided for @missionBadgeCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}개'**
  String missionBadgeCount(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
