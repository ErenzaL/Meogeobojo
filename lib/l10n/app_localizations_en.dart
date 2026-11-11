// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonLater => 'Not now';

  @override
  String get commonSave => 'Save';

  @override
  String get tryAgainLater => 'Please try again in a moment.';

  @override
  String get mascotSemantics => '먹어보조 mascot';

  @override
  String get errPermissionDenied =>
      'You don\'t have permission to do that. Please sign in again and retry.';

  @override
  String get navHome => 'Home';

  @override
  String get navCommunity => 'Food Talk';

  @override
  String get navMap => 'Map';

  @override
  String get navRecords => 'Records';

  @override
  String get navProfile => 'My';

  @override
  String get languageSheetTitle => 'Language';

  @override
  String get languageButtonTooltip => 'Language';

  @override
  String get profileLanguage => 'Language';

  @override
  String homeHeroAround(String university) {
    return 'Around $university';
  }

  @override
  String get homeHeroTitle => 'What should we\neat today?';

  @override
  String get homeHeroSubtitle => 'A tasty meal is waiting for you!';

  @override
  String get homeSearchLabel => 'Search';

  @override
  String get searchHint => 'Search menus or restaurants';

  @override
  String get homeNotificationsLabel => 'Notifications';

  @override
  String get homeNotificationsSoon => 'Notifications are coming soon.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'No new notifications';

  @override
  String get notificationsEmptyHint =>
      'News will show up here when it is posted.';

  @override
  String get notificationsNew => 'New';

  @override
  String get notificationsOpenLink => 'Learn more';

  @override
  String notificationsBellUnread(int count) {
    return 'Notifications, $count unread';
  }

  @override
  String get notificationsJustNow => 'Just now';

  @override
  String notificationsMinutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String notificationsHoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String notificationsDaysAgo(int n) {
    return '$n d ago';
  }

  @override
  String get homeMore => 'See all >';

  @override
  String get homeNearbyTitle => 'Restaurants near campus';

  @override
  String get homeMenuTitle => 'Browse by menu';

  @override
  String get homeBannerLabel => 'Today\'s meal pick';

  @override
  String get homeBannerTitle => 'How about this today?';

  @override
  String get homeBannerSubtitle => 'Check out popular spots right now!';

  @override
  String get homeBannerCta => 'See recommendations';

  @override
  String get categoryAll => 'All';

  @override
  String get categoryKorean => 'Korean';

  @override
  String get categoryWestern => 'Western';

  @override
  String get categoryChinese => 'Chinese';

  @override
  String get categoryJapanese => 'Japanese';

  @override
  String get categoryCafeDessert => 'Cafe & dessert';

  @override
  String get categorySnack => 'Snacks';

  @override
  String get categoryEtc => 'Other';

  @override
  String get menuMalatang => 'Malatang';

  @override
  String get menuPorkCutlet => 'Pork cutlet';

  @override
  String get menuNaengmyeon => 'Cold noodles';

  @override
  String get menuSoondubu => 'Soft tofu stew';

  @override
  String get menuChicken => 'Fried chicken';

  @override
  String get menuTteokbokki => 'Tteokbokki';

  @override
  String get menuPasta => 'Pasta';

  @override
  String get menuAmericano => 'Americano';

  @override
  String get restaurantLoadFailedTitle => 'Couldn\'t load restaurants';

  @override
  String get restaurantLoadFailedMessage => 'Couldn\'t load restaurant info.';

  @override
  String get restaurantEmptyTitle => 'No nearby restaurants found yet';

  @override
  String get universityChange => 'Change campus';

  @override
  String restaurantListSubtitle(String university, String category) {
    return '$university · $category · Nearest first';
  }

  @override
  String restaurantTagDistance(String tag, String distance) {
    return '$tag · $distance from campus';
  }

  @override
  String restaurantDistanceFromSchool(String distance) {
    return '$distance from campus';
  }

  @override
  String restaurantDistanceStraight(String distance) {
    return '$distance from campus (straight line)';
  }

  @override
  String get restaurantNoAddress => 'No address available';

  @override
  String get restaurantNoPhone => 'No phone number listed';

  @override
  String get restaurantDataNotice =>
      'Photos, ratings, menus, prices and opening hours aren\'t available yet. Check Kakao Map for details.';

  @override
  String get restaurantOpenKakaoMap => 'View on Kakao Map';

  @override
  String get restaurantLinkOpenFailed => 'Couldn\'t open that link.';

  @override
  String get restaurantErrNetwork => 'Check your internet connection.';

  @override
  String get restaurantErrTimeout =>
      'This is taking too long. Please try again shortly.';

  @override
  String get restaurantErrQuota =>
      'Too many requests. Please try again shortly.';

  @override
  String get restaurantErrAuth =>
      'Authentication with the restaurant search server failed.';

  @override
  String get restaurantErrInvalid => 'The search conditions are invalid.';

  @override
  String get restaurantErrUpstream =>
      'The server had a problem fetching restaurants.';

  @override
  String get restaurantErrUnknown => 'Something went wrong.';

  @override
  String get searchIdleTitle => 'What are you craving?';

  @override
  String searchIdleMessage(String university) {
    return 'We\'ll search around $university.';
  }

  @override
  String searchNoResultsTitle(String query) {
    return 'No results for \'$query\'';
  }

  @override
  String get searchNoResultsMessage => 'Try another keyword or change campus.';

  @override
  String searchResultsSummary(String university, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0 near $university, nearest first';
  }

  @override
  String mapStatusLoading(String university) {
    return '$university · Loading restaurants…';
  }

  @override
  String mapStatusError(String university) {
    return '$university · Couldn\'t load restaurants';
  }

  @override
  String mapStatusCount(String university, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '1 place',
    );
    return '$university · $_temp0 nearby';
  }

  @override
  String get mapErrorTitle => 'Couldn\'t load the map';

  @override
  String get mapErrorMessage =>
      'Please try again shortly. The restaurant list and search still work.';

  @override
  String get universitySelect => 'Select campus';

  @override
  String universitySelectCurrent(String name) {
    return 'Select campus, currently $name';
  }

  @override
  String get universitySearchHint => 'Search campus name';

  @override
  String get universityLoadFailed => 'Couldn\'t load the campus list';

  @override
  String get universityNoMatch => 'No matching campus';

  @override
  String get universityFallbackName => 'campus';

  @override
  String get cityAsan => 'Asan';

  @override
  String get cityCheonan => 'Cheonan';

  @override
  String get favoriteAdd => 'Add to favorites';

  @override
  String get favoriteRemove => 'Remove from favorites';

  @override
  String get favoriteSaveFailed =>
      'Couldn\'t save your favorite. Please try again shortly.';

  @override
  String get recordsEmptyTitle => 'No records yet';

  @override
  String get recordsEmptyMessage => 'Logging what you ate is coming soon.';

  @override
  String get communityTitle => 'Food Talk is coming soon';

  @override
  String get communityMessage =>
      'We\'re working hard so you can chat about\nfood with friends from your campus!';

  @override
  String recommendStrategyProximity(String university) {
    return 'Nearest to $university';
  }

  @override
  String get recommendExplainBaseline =>
      'There\'s no popularity or taste data yet, so we show restaurants closest to campus first. Personalized picks are coming soon.';

  @override
  String get recommendStrategyPreferences => 'Filtered by your conditions';

  @override
  String recommendExplainPreferences(int count, int total) {
    return 'We applied your saved distance and cuisine conditions: $count of $total places, nearest first. Budget, companions and taste tags aren\'t applied yet, and distance is a straight-line estimate. Personalized picks are coming soon.';
  }

  @override
  String get recommendNoMatchTitle => 'No restaurants match your conditions';

  @override
  String get recommendNoMatchMessage =>
      'Try changing the distance or cuisine conditions.';

  @override
  String get profileGuestTitle => 'Sign in to save your favorite spots';

  @override
  String get profileGuestSubtitle =>
      'Browsing and search work without signing in.';

  @override
  String get profileLoginButton => 'Sign in / Sign up';

  @override
  String profileGreeting(String nickname) {
    return 'Hello, $nickname';
  }

  @override
  String get profileGreetingSub => 'Ready to find a tasty meal today?';

  @override
  String get profileEditProfile => 'Edit profile →';

  @override
  String profileCampusHint(String city) {
    return '$city · Tap to change';
  }

  @override
  String get profileCampusHintNoCity => 'Tap to change';

  @override
  String get profileStatSaved => 'Saved places';

  @override
  String get profileStatRecords => 'My records';

  @override
  String get profileStatPlans => 'Upcoming plans';

  @override
  String get profileStatUnavailable => 'Soon';

  @override
  String get profileSaved => 'Saved restaurants';

  @override
  String profileSavedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '1 place',
    );
    return '$_temp0';
  }

  @override
  String get profileRecords => 'My records';

  @override
  String get profilePreferences => 'My taste settings';

  @override
  String get profileAccount => 'Account settings';

  @override
  String get profileLogout => 'Sign out';

  @override
  String get profileDefaultNickname => '먹어보조 user';

  @override
  String get savedLoadFailed => 'Couldn\'t load your saved restaurants';

  @override
  String get savedEmptyTitle => 'No saved restaurants yet';

  @override
  String get savedEmptyMessage =>
      'Tap the heart on a restaurant you like to save it.';

  @override
  String savedHiddenNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved places aren\'t',
      one: '1 saved place isn\'t',
    );
    return '$_temp0 in the current campus results, so details can\'t be shown. Select the campus they belong to in order to see them.';
  }

  @override
  String get accountNickname => 'Nickname';

  @override
  String get accountNicknameEdit => 'Change nickname';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountLoginMethod => 'Sign-in method';

  @override
  String get accountProviderKakao => 'Kakao';

  @override
  String get accountProviderEmail => 'Email';

  @override
  String get authContinueKakao => 'Continue with Kakao';

  @override
  String get authEmailLogin => 'Sign in with email';

  @override
  String get authEmailSignUp => 'Sign up with email';

  @override
  String get authBrowseAsGuest => 'Continue without signing in →';

  @override
  String get authKakaoWaiting => 'Signing in with Kakao…';

  @override
  String get legalTerms => 'Terms of Service';

  @override
  String get legalPrivacy => 'Privacy Policy';

  @override
  String get legalNotPublished => 'This document hasn\'t been published yet.';

  @override
  String get legalOpenFailed => 'Couldn\'t open the link.';

  @override
  String get authEmailLoginTitle => 'Sign in with email';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordConfirmLabel => 'Confirm password';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authPasswordShow => 'Show password';

  @override
  String get authPasswordHide => 'Hide password';

  @override
  String get authLoginButton => 'Sign in';

  @override
  String get authForgotPasswordLink => 'Forgot your password?';

  @override
  String get authNoAccountSignUp => 'No account yet? Sign up';

  @override
  String get authHaveAccountLogin => 'I already have an account. Sign in';

  @override
  String get authSignUpTitle => 'Sign up with email';

  @override
  String get authSignUpSubtitle =>
      'Create an account with your email and a password. You\'ll need to verify your email afterwards.';

  @override
  String get authSignUpButton => 'Create account';

  @override
  String authPasswordRule(int min) {
    return 'Use at least $min characters.';
  }

  @override
  String get authVerifyTitle => 'Check your email';

  @override
  String authVerifyMessage(String email) {
    return 'We sent a verification email to $email. Tap the link in it to finish signing up.';
  }

  @override
  String get authVerifyNotSignedIn =>
      'You won\'t be signed in until you verify.';

  @override
  String get authVerifyResend => 'Resend verification email';

  @override
  String authVerifyResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authVerifyResent => 'Verification email sent again.';

  @override
  String get authVerifyBackToLogin => 'Back to sign in';

  @override
  String get authForgotTitle => 'Reset your password';

  @override
  String get authForgotMessage =>
      'Enter your email and we\'ll send you a link to reset your password.';

  @override
  String get authForgotSend => 'Send reset email';

  @override
  String get authForgotResend => 'Send again';

  @override
  String authForgotSent(String email) {
    return 'If an account exists for $email, we\'ve sent a reset link. Check your inbox.';
  }

  @override
  String get authResetTitle => 'Set a new password';

  @override
  String get authResetMessage => 'Enter the password you\'d like to use.';

  @override
  String get authResetButton => 'Change password';

  @override
  String get authResetSuccess => 'Your password has been changed.';

  @override
  String get errEmailRequired => 'Enter your email.';

  @override
  String get errEmailInvalid => 'That doesn\'t look like a valid email.';

  @override
  String get errPasswordRequired => 'Enter your password.';

  @override
  String errPasswordShort(int min) {
    return 'Password must be at least $min characters.';
  }

  @override
  String get errPasswordMismatch => 'The passwords don\'t match.';

  @override
  String get authErrInvalidCredentials => 'Incorrect email or password.';

  @override
  String get authErrEmailNotConfirmed =>
      'Your email isn\'t verified yet. Open the link in the email we sent.';

  @override
  String get authErrEmailTaken =>
      'This email is already registered. Please sign in.';

  @override
  String get authErrInvalidEmail => 'That email address isn\'t valid.';

  @override
  String get authErrWeakPassword =>
      'That password is too weak. Make it longer or more complex.';

  @override
  String get authErrSamePassword =>
      'Please choose a password different from your old one.';

  @override
  String get authErrKakaoCancelled => 'Kakao sign-in was cancelled.';

  @override
  String get authErrKakaoConfig =>
      'There\'s a problem with Kakao sign-in setup. Try again shortly, and contact us if it continues.';

  @override
  String get authErrDeepLinkMissing =>
      'Sign-in wasn\'t completed. It may have been cancelled, or the app didn\'t receive the result. Please try again.';

  @override
  String get authErrSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get authErrLinkExpired =>
      'This link has expired or was already used. Please request a new one.';

  @override
  String get authErrRateLimited =>
      'Too many attempts. Please try again in a moment.';

  @override
  String get authErrNetwork => 'Check your connection and try again.';

  @override
  String get authErrTimeout => 'This is taking too long. Please try again.';

  @override
  String get authErrPasswordReset =>
      'Couldn\'t reset the password. Please try again.';

  @override
  String get authErrProfileLoad =>
      'Couldn\'t load your profile. Please try again.';

  @override
  String get authErrUnknown => 'Something went wrong. Please try again.';

  @override
  String get nicknameSetupTitle => 'What should we call you?';

  @override
  String get nicknameSetupSubtitle => 'Choose a nickname to use in 먹어보조.';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get nicknameHint => 'Enter a nickname';

  @override
  String get nicknameNext => 'Next';

  @override
  String nicknameRule(int min, int max) {
    return '$min–$max characters.';
  }

  @override
  String get nicknameErrEmpty => 'Enter a nickname.';

  @override
  String nicknameErrTooShort(int min) {
    return 'Nickname must be at least $min characters.';
  }

  @override
  String nicknameErrTooLong(int max) {
    return 'Nickname can be at most $max characters.';
  }

  @override
  String get nicknameErrInvalidChars =>
      'The nickname contains characters that can\'t be used.';

  @override
  String get nicknameSaveFailed =>
      'Couldn\'t save your nickname. Please try again.';

  @override
  String get nicknameUpdated => 'Nickname updated.';

  @override
  String get homeCampusMeals => 'Campus Meals';

  @override
  String get mealPageTitle => 'This Week\'s Campus Meals';

  @override
  String get mealToday => 'Today';

  @override
  String get mealPrevWeek => 'Previous week';

  @override
  String get mealNextWeek => 'Next week';

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
  String get mealBreakfast => 'Breakfast';

  @override
  String get mealLunch => 'Lunch';

  @override
  String get mealDinner => 'Dinner';

  @override
  String get mealSelectCafeteria => 'Choose cafeteria';

  @override
  String get mealKindStudent => 'Student cafeteria';

  @override
  String get mealKindDormitory => 'Dormitory cafeteria';

  @override
  String get mealKindStaff => 'Faculty & staff cafeteria';

  @override
  String get mealKindOther => 'Cafeteria';

  @override
  String mealCafeteriaNth(String kind, int number) {
    return '$kind $number';
  }

  @override
  String get mealEmptyTitle => 'No menu information has been registered.';

  @override
  String get mealNotCollectedWeek =>
      'This week\'s menu hasn\'t been added yet.';

  @override
  String get mealNotCollectedHint =>
      'It will appear here once official information is verified.';

  @override
  String get mealClosedTitle => 'Not served at this time';

  @override
  String get mealClosedHint => 'Confirmed by the source.';

  @override
  String get mealNoMenuTitle => 'No menu has been published';

  @override
  String get mealNoMenuHint => 'The source states that no menu is published.';

  @override
  String get mealNoCafeteria =>
      'Campus meal information for this university hasn\'t been added yet.';

  @override
  String get mealLoadFailed => 'Couldn\'t load campus meals';

  @override
  String get mealLoadFailedHint => 'Check your connection and try again.';

  @override
  String mealPrice(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return '₩$priceString';
  }

  @override
  String mealServingTime(String start, String end) {
    return 'Served $start – $end';
  }

  @override
  String get mealSource => 'Source';

  @override
  String get mealOpenSource => 'Open source';

  @override
  String mealVerifiedAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Verified $dateString';
  }

  @override
  String get mealKindMain => 'Main';

  @override
  String get mealKindSide => 'Side';

  @override
  String get mealKindSoup => 'Soup';

  @override
  String get mealKindRice => 'Rice';

  @override
  String get settingsAccountTitle => 'Account';

  @override
  String get settingsAppTitle => 'App Settings';

  @override
  String get themeTitle => 'Appearance';

  @override
  String get themeLight => 'Light Mode';

  @override
  String get themeDark => 'Dark Mode';

  @override
  String get themeSystem => 'Use Device Settings';

  @override
  String get categoryChicken => 'Chicken';

  @override
  String get categoryFastFood => 'Fast food';

  @override
  String get categoryGlobal => 'Global Cuisine';

  @override
  String get cuisineAll => 'All';

  @override
  String get cuisineVietnamese => 'Vietnamese';

  @override
  String get cuisineThai => 'Thai';

  @override
  String get cuisineIndian => 'Indian';

  @override
  String get cuisineMexican => 'Mexican';

  @override
  String get cuisineOther => 'Other global';

  @override
  String get categoryGlobalNote =>
      'Only places Kakao files under Asian, Mexican, etc., nearest first. We never guess a cuisine from a restaurant\'s name, and some places may be missing.';

  @override
  String get cuisineEmptyHint =>
      'We only search nearby, so there may be none around this campus or they may be out of range. Try another cuisine or campus.';

  @override
  String categoryHeading(String category) {
    return '$category restaurants';
  }

  @override
  String get categorySortDistance => 'Nearest';

  @override
  String get categorySortName => 'Name';

  @override
  String categoryResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '1 place',
    );
    return '$_temp0';
  }

  @override
  String get categoryEmptyTitle =>
      'We couldn\'t find restaurants in this category.';

  @override
  String get categoryEmptyHint =>
      'We search the nearest places. Try another category or campus.';

  @override
  String get categoryResultsNote =>
      'Nearest matches from Kakao search. This may not be every place.';

  @override
  String get categoryAllTitle => 'All categories';

  @override
  String get categoryOpenAll => 'Show all categories';

  @override
  String categoryLocation(String university, String city) {
    return '$university · $city';
  }

  @override
  String get authReasonFavorite => 'Sign in to save restaurants';

  @override
  String get authReasonRecords => 'Sign in to log what you eat';

  @override
  String get authReasonCommunity => 'Sign in to post in Food Talk';

  @override
  String get authReasonProfile => 'Sign in to edit your profile';

  @override
  String get authPromptBody => 'Browsing and search work without signing in.';

  @override
  String get authPromptLogin => 'Sign in';

  @override
  String get onbStepLabel => 'STEP 1–4';

  @override
  String get onbTitle => 'What should I eat today?';

  @override
  String get onbSubtitle => 'Shall we find places that suit you?';

  @override
  String get onbCampusLabel => 'Current campus';

  @override
  String get onbBadgeRequired => 'Required';

  @override
  String get onbBadgeOptional => 'Optional';

  @override
  String get onbBudgetTitle => 'Budget per meal';

  @override
  String get onbBudgetDesc =>
      'All amounts are per person. Pick “or more” when you want to spend a bit extra on a special day.';

  @override
  String onbBudgetMax(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return 'Up to ₩$amountString';
  }

  @override
  String onbBudgetMin(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '₩$amountString or more';
  }

  @override
  String get onbAny => 'No preference';

  @override
  String get onbNeedBudget => 'Please pick a budget.';

  @override
  String get onbDistanceTitle => 'How far will you go?';

  @override
  String get onbDistanceDesc =>
      'Measured from campus. Times are rough estimates converted from straight-line distance.';

  @override
  String onbWalkMinutes(int minutes) {
    return '$minutes min walk';
  }

  @override
  String onbDriveMinutes(int minutes) {
    return '$minutes min drive';
  }

  @override
  String get onbWalkLabel => 'Walking';

  @override
  String get onbDriveLabel => 'Driving';

  @override
  String get onbNeedDistance => 'Please pick a distance.';

  @override
  String get onbOriginTitle => 'Starting point: campus center';

  @override
  String get onbOriginHint =>
      'Gate coordinates aren\'t available yet, so distance is measured in a straight line from the campus center.';

  @override
  String get onbCompanionTitle => 'Who are you eating with?';

  @override
  String get onbCompanionDesc =>
      'Pick who you usually eat with. You can choose more than one.';

  @override
  String get companionSolo => 'Solo';

  @override
  String get companionFriends => '2–3 friends';

  @override
  String get companionGroup => '4 or more';

  @override
  String get companionSenior => 'With a senior';

  @override
  String get companionJunior => 'With a junior';

  @override
  String get companionProfessor => 'With a professor';

  @override
  String get onbFoodTitle => 'Foods you like';

  @override
  String get onbFoodDesc => 'Pick as many as you like, or skip this.';

  @override
  String get cuisineKorean => 'Korean';

  @override
  String get cuisineJapanese => 'Japanese';

  @override
  String get cuisineChinese => 'Chinese';

  @override
  String get cuisineSnack => 'Snacks';

  @override
  String get cuisineCafe => 'Cafe';

  @override
  String get cuisineWestern => 'Western';

  @override
  String get cuisineSalad => 'Salad';

  @override
  String get cuisineAny => 'Anything';

  @override
  String get tagSpicy => 'Spicy';

  @override
  String get tagHearty => 'Hearty';

  @override
  String get tagValue => 'Good value';

  @override
  String get tagLight => 'Light';

  @override
  String get onbUntriedTitle => 'Try new dishes first';

  @override
  String get onbUntriedDesc =>
      'Recently eaten types get pushed back, based on your records. Applies once records are available.';

  @override
  String get onbFilterNote =>
      'Right now only distance and cuisine affect results. Budget, companions and taste tags are saved so they can be applied once price and seating data exist.';

  @override
  String onbCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places match',
      one: '1 place matches',
    );
    return '$_temp0 now';
  }

  @override
  String get onbCountUnknown => 'Loading nearby places…';

  @override
  String get onbCountNote => 'Distance & cuisine only';

  @override
  String get onbClearAll => 'Clear all';

  @override
  String get onbRandom => 'Random';

  @override
  String get onbViewRecs => 'See picks';

  @override
  String onbViewRecsCount(int count) {
    return 'See $count picks';
  }

  @override
  String get onbSave => 'Save';

  @override
  String get onbRandomNone => 'No restaurants match your conditions.';

  @override
  String get onbLogout => 'Sign out';

  @override
  String get prefsEditTitle => 'My taste settings';

  @override
  String get prefsEditSubtitle => 'Update the conditions you saved.';

  @override
  String get prefsSaved => 'Your preferences are saved.';

  @override
  String get prefsLoadFailed => 'Couldn\'t load your saved preferences';

  @override
  String get prefsSaveFailed =>
      'Couldn\'t save. Your selections are still here, so please try again.';

  @override
  String get homeTitle => 'What should I eat today?';

  @override
  String homeSubtitle(String part, String time, String origin) {
    return '$part · $time · from $origin';
  }

  @override
  String get dayPartBreakfast => 'Breakfast';

  @override
  String get dayPartLunch => 'Lunch';

  @override
  String get dayPartDinner => 'Dinner';

  @override
  String get dayPartLateNight => 'Late night';

  @override
  String get homeRestartTooltip => 'Start over';

  @override
  String get homeProfileTooltip => 'Profile';

  @override
  String homeOriginChip(String origin) {
    return 'From $origin';
  }

  @override
  String get homeConditionsChip => 'Filters';

  @override
  String homeConditionsActive(int count) {
    return '$count filters on';
  }

  @override
  String homeHeroRank(int total, int rank) {
    return '#$rank of $total';
  }

  @override
  String homePriceFrom(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return '$priceString~';
  }

  @override
  String homeMetaReviews(int count) {
    return '$count reviews';
  }

  @override
  String homeReasonCuisine(String cuisine) {
    return '$cuisine, the food you picked';
  }

  @override
  String get homeReasonBudget => 'Within your budget';

  @override
  String get homeReasonClosest => 'Closest to you';

  @override
  String homeReasonWalk(int minutes) {
    return '$minutes min on foot';
  }

  @override
  String get homeArrival => 'Arrive at';

  @override
  String get homeLastOrder => 'Last order';

  @override
  String homeWalkAbout(int minutes) {
    return 'About $minutes min walk';
  }

  @override
  String homeSlackHM(int hours, int minutes) {
    return '$hours h $minutes min to spare';
  }

  @override
  String homeSlackH(int hours) {
    return '$hours h to spare';
  }

  @override
  String homeSlackM(int minutes) {
    return '$minutes min to spare';
  }

  @override
  String get homeNoInfo => 'No info';

  @override
  String get homeClosesBeforeArrival => 'Closes before you arrive';

  @override
  String get homeDirections => 'Directions';

  @override
  String get homeInfo => 'Info';

  @override
  String get homeAltTitle => 'Not feeling it?';

  @override
  String get homePickForMe => 'Pick one for me';

  @override
  String get homeNextPick => 'Next pick ›';

  @override
  String get homePrevPick => '‹ Previous';

  @override
  String get homeRestart => 'Start over';

  @override
  String get homePromptTitle => 'Set your conditions to get a pick';

  @override
  String get homePromptMessage =>
      'Choose a budget or distance, or tap “Get today’s pick”.';

  @override
  String get homeGameButton => 'Choose with a game';

  @override
  String get homeGameTitle => 'What to eat? Play for it!';

  @override
  String get homeGameSub => 'Picks from places that match your conditions.';

  @override
  String get homeGameRoulette => 'Roulette';

  @override
  String get homeGameRouletteHint => 'Spin and go where it stops';

  @override
  String get homeGameLadder => 'Ladder';

  @override
  String get homeGameLadderHint => 'Pick a line and follow it down';

  @override
  String get homeGameCards => 'Pick a card';

  @override
  String get homeGameCardsHint => 'Flip one and see';

  @override
  String get homeGameSpin => 'Spin!';

  @override
  String get homeGameSpinning => 'Spinning…';

  @override
  String get homeGameLadderPrompt => 'Pick a line to start';

  @override
  String get homeGameCardsPrompt => 'Pick one card';

  @override
  String get homeGameResult => 'Today it\'s…';

  @override
  String get homeGameAgain => 'Play again';

  @override
  String get homeGameConfirm => 'Go here';

  @override
  String get homeGameBack => 'Other games';

  @override
  String homeGameChosen(String name) {
    return 'Picked $name. See it in the top card.';
  }

  @override
  String homeCmpCloser(int minutes) {
    return '$minutes min closer';
  }

  @override
  String homeCmpCheaper(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '₩$amountString cheaper';
  }

  @override
  String get homeCmpRating => 'Rated higher';

  @override
  String get homeCmpLater => 'Open later';

  @override
  String get homeStatusOrderable => 'Ordering open';

  @override
  String homeStatusClosesAt(String time) {
    return 'Last order $time';
  }

  @override
  String homeSeeOnMap(int count) {
    return 'See $count matching places on the map';
  }

  @override
  String get homeEmptyTitle => 'No place matches';

  @override
  String get homeEmptyMessage => 'Loosen a condition to see more.';

  @override
  String get homeMealTitle => 'Today\'s cafeteria';

  @override
  String homeMealChipNow(String meal) {
    return '$meal now';
  }

  @override
  String homeMealChipToday(String meal) {
    return '$meal today';
  }

  @override
  String homeMealChipTomorrow(String meal) {
    return '$meal tomorrow';
  }

  @override
  String get homeMealNone => 'No upcoming cafeteria menu has been added yet.';

  @override
  String homeMealAvgCaption(String place) {
    return 'Average lunch · restaurants within a 15 min walk of $place';
  }

  @override
  String get homeMealBarCafeteria => 'Cafeteria';

  @override
  String get homeMealBarOutside => 'Outside';

  @override
  String get homeMealSavingPre =>
      'Eating 20 meals a month at the cafeteria saves ';

  @override
  String get homeMealSavingPost => '.';

  @override
  String get homeMealNoCompare =>
      'Not enough price data to compare yet. Both cafeteria and outside prices are needed.';

  @override
  String get homeMealWeekly => 'This week\'s menu';

  @override
  String get homeMealCompare => 'Compare with outside';

  @override
  String get homeCompareSoon => 'The price comparison screen is coming soon.';

  @override
  String get originCampusCenter => 'Campus center';

  @override
  String get originSheetTitle => 'Where are you starting from?';

  @override
  String get originSheetDesc =>
      'Maps and recommendations are re-sorted by walking distance from the spot you pick. Building positions are demo examples.';

  @override
  String get originGroupGates => 'Gates';

  @override
  String get originGroupColleges => 'Colleges';

  @override
  String get originGroupBuildings => 'Main buildings';

  @override
  String get originGroupPins => 'My pins';

  @override
  String get originNoPins => 'No saved pins yet.';

  @override
  String originNearest(String name, int minutes) {
    return 'Nearest: $name · $minutes min walk';
  }

  @override
  String get originNearestNone => 'No matching place nearby';

  @override
  String get originPickOnMap => 'Drop a pin on the map';

  @override
  String get originPinPickerTitle => 'Choose a starting point';

  @override
  String get originPinPickerHint =>
      'Move the map to put the pin where you want.';

  @override
  String get originPinConfirm => 'Use this spot';

  @override
  String get originPinNameTitle => 'Pin name';

  @override
  String get originPinNameHint => 'e.g. In front of the dorm';

  @override
  String originPinDefaultName(int number) {
    return 'My pin $number';
  }

  @override
  String get originPinDelete => 'Delete pin';

  @override
  String get originPinFailed => 'Couldn\'t read the position. Try again.';

  @override
  String get condTitle => 'Filters';

  @override
  String get condSubtitle => 'Applied the same on Home, Map and Search.';

  @override
  String get condMust => 'Must-haves';

  @override
  String get condMustHint => 'Places that don\'t fit are hidden';

  @override
  String get condMissingNote =>
      'Places with no price or hours info are kept, not hidden.';

  @override
  String get condChange => 'Change';

  @override
  String get condOpenNow => 'Only places I can order from now';

  @override
  String get condOpenNowHint =>
      'Places whose last order isn\'t before your arrival. Turn off only when planning for later.';

  @override
  String get condCuisine => 'Cuisine';

  @override
  String get condOps => 'Hours & facilities';

  @override
  String get condAmenityNoBreak => 'No break time';

  @override
  String get condAmenityParking => 'Parking';

  @override
  String get condAmenityLocalCurrency => 'Local currency (Asan Pay)';

  @override
  String get condAmenityFast => 'Fast turnover';

  @override
  String get condAmenityTakeout => 'Takeout';

  @override
  String get condAmenityLate => 'Open until 10 pm';

  @override
  String get condSoft => 'Shapes the order';

  @override
  String get condParty => 'How many are eating?';

  @override
  String get condPartyFew => '2–3 people';

  @override
  String get condNeeds => 'What you need';

  @override
  String get condNeedQuiet => 'Quiet talk';

  @override
  String get condNeedQuick => 'Quick meal';

  @override
  String get condNeedGenerous => 'Generous portions';

  @override
  String get condUntried => 'Try new places first';

  @override
  String condUntriedHint(int count) {
    return 'Based on $count logged meals · counted per restaurant';
  }

  @override
  String get condSort => 'Sort';

  @override
  String get condSortRecommended => 'Recommended';

  @override
  String get condSortPrice => 'Price';

  @override
  String get condSortRating => 'Rating';

  @override
  String get condSoftNote =>
      'For now the order is nearest first. Party size and needs will shape it once data exists.';

  @override
  String get condResetAll => 'Clear all';

  @override
  String get condResetThis => 'Reset this';

  @override
  String condShowCount(int count) {
    return 'Show $count places';
  }

  @override
  String get condNoMatch => 'No place matches';

  @override
  String get condRestart => 'Go back to the start and set up again';

  @override
  String get condRestartTitle => 'Start over?';

  @override
  String get condRestartBody =>
      'This resets your conditions and starting point and reopens your taste setup.';

  @override
  String get condRestartAction => 'Start over';

  @override
  String get condRestartGuestDone =>
      'Conditions and starting point were reset.';

  @override
  String get restaurantAboutTitle => 'About';

  @override
  String get restaurantMenuTitle => 'Menu';

  @override
  String get restaurantMenuSoldOut => 'Sold out';

  @override
  String get authReasonContribute => 'Sign in to leave reviews and photos.';

  @override
  String get reviewsTitle => 'Reviews';

  @override
  String reviewsSummary(String avg, int count) {
    return 'Average $avg · $count';
  }

  @override
  String get reviewsEmpty => 'No reviews yet. Be the first to write one.';

  @override
  String get reviewWrite => 'Write a review';

  @override
  String get reviewEditMine => 'Edit my review';

  @override
  String get reviewMine => 'My review';

  @override
  String get reviewAuthor => 'Student';

  @override
  String get reviewEditorHint =>
      'Tell us about the food, price, atmosphere (optional)';

  @override
  String get reviewRating => 'Rating';

  @override
  String get reviewSave => 'Save';

  @override
  String get reviewDelete => 'Delete';

  @override
  String get reviewDeleteConfirm => 'Delete this review?';

  @override
  String get reviewSaved => 'Review saved.';

  @override
  String get reviewDeleted => 'Review deleted.';

  @override
  String get reviewSaveFailed => 'Couldn\'t save. Please try again.';

  @override
  String get reviewRatingRequired => 'Please choose a rating.';

  @override
  String get reviewStatusVisible => 'Visible';

  @override
  String get reviewStatusHidden =>
      'Hidden by a moderator. Other students can\'t see it.';

  @override
  String get reviewStatusRemoved => 'Removed.';

  @override
  String get reportAction => 'Report';

  @override
  String get reportTitle => 'Report this review?';

  @override
  String get reportReasonAbuse => 'Abuse';

  @override
  String get reportReasonSpam => 'Spam or ads';

  @override
  String get reportReasonFalse => 'Not accurate';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportSend => 'Report';

  @override
  String get reportSent => 'Reported. A moderator will take a look.';

  @override
  String get reportAlready => 'You already reported this review.';

  @override
  String get reportFailed => 'Couldn\'t send the report. Please try again.';

  @override
  String get photoUploadButton => 'Add a photo';

  @override
  String get photoSheetTitle => 'Add a photo';

  @override
  String get photoKindRestaurant => 'Restaurant photo';

  @override
  String get photoKindMenu => 'Menu photo';

  @override
  String get photoPick => 'Choose a photo';

  @override
  String get photoChange => 'Choose another';

  @override
  String get photoCaptionHint => 'Caption (optional)';

  @override
  String get photoConsent =>
      'I agree this photo may be shown in 먹어보조 after review.';

  @override
  String get photoPrivateNote =>
      'Only you can see it until it has been reviewed.';

  @override
  String get photoSubmit => 'Submit';

  @override
  String get photoSubmitting => 'Uploading…';

  @override
  String get photoSubmitted =>
      'Submitted. It will be published after a moderator checks it.';

  @override
  String get photoTooLarge => 'The photo must be 5 MB or smaller.';

  @override
  String get photoFailed => 'Couldn\'t upload. Please try again.';

  @override
  String get photoDuplicate => 'You already submitted this photo.';

  @override
  String get photoTooMany =>
      'Too many photos are waiting for review. Please try again later.';

  @override
  String get myContribTitle => 'My reviews & photos';

  @override
  String get myContribOpen => 'See my reviews & photos';

  @override
  String get myContribReviews => 'My reviews';

  @override
  String get myContribPhotos => 'My photos';

  @override
  String get myContribEmpty => 'You haven\'t left any reviews or photos yet.';

  @override
  String get myContribLoadFailed => 'Couldn\'t load.';

  @override
  String get contribStatusPending => 'In review';

  @override
  String get contribStatusApproved => 'Published';

  @override
  String get contribStatusRejected => 'Not published';

  @override
  String contribRejectedReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get contribWithdraw => 'Withdraw';

  @override
  String get contribWithdrawConfirm =>
      'Withdraw this submission? The photo will be deleted.';

  @override
  String get contribWithdrawn => 'Withdrawn.';

  @override
  String get missionActionPickPlace =>
      'Pick a restaurant and leave it on its page. It counts for the mission right away.';

  @override
  String get restaurantGalleryTitle => 'Photos';

  @override
  String get restaurantMenuRecommended => 'Recommended';

  @override
  String restaurantPriceWon(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return '₩$priceString';
  }

  @override
  String get mealBreakfastProgram => 'Breakfast · 1,000-won Breakfast';

  @override
  String mealHeading(String day, String meal) {
    return '$day $meal · cafeteria';
  }

  @override
  String get mealDayTomorrow => 'Tomorrow';

  @override
  String get myTitle => 'My page';

  @override
  String get myActivityTitle => 'My activity';

  @override
  String get recordsPageTitle => 'My records';

  @override
  String get recordsSubtitle => 'A food diary only you can see';

  @override
  String get recordsAdd => 'Add record';

  @override
  String recordsReportTitle(int month) {
    return '$month report';
  }

  @override
  String get recordsReportBasis => 'Based on this month\'s records';

  @override
  String get recordsStatMeals => 'Meals out';

  @override
  String get recordsStatSpend => 'Total spent';

  @override
  String get recordsStatAvg => 'Avg per meal';

  @override
  String get recordsReportHint =>
      'Log places you ate and we\'ll sum up this month\'s spending and favorites.';

  @override
  String recordsTabEaten(String count) {
    return 'Eaten $count';
  }

  @override
  String recordsTabWant(String count) {
    return 'Want to go $count';
  }

  @override
  String get recordsNoRecordsTitle => 'No records yet';

  @override
  String get recordsNoRecordsBody =>
      'Log where, what, how much and with whom you ate to build your own food diary.';

  @override
  String get recordsFirst => 'Add your first record';

  @override
  String communitySubtitle(String campus) {
    return '$campus student community';
  }

  @override
  String get communityMyActivity => 'My activity';

  @override
  String get communityFilterAll => 'All';

  @override
  String get communityFilterReviews => 'Reviews';

  @override
  String get communityFilterMeets => 'Eat together';

  @override
  String get communityFilterQuestions => 'Questions';

  @override
  String get communityComposerTitle => 'Want to share what you ate today?';

  @override
  String get communityWriteReview => 'Write a review';

  @override
  String get communityStartMeet => 'Invite to eat';

  @override
  String get communityAsk => 'Ask a question';

  @override
  String get communityFeedTitle => 'Around campus';

  @override
  String get communitySortLatest => 'Newest';

  @override
  String get communityEmptyTitle => 'No stories yet';

  @override
  String get communityEmptyBody =>
      'Post what you ate or look for someone to eat with.';

  @override
  String get communityComposeSoon => 'Posting on Food Talk is coming soon.';

  @override
  String get mapPageTitle => 'Nearby places';

  @override
  String get mapOpenNowChip => 'Open now';

  @override
  String mapMatchCount(int count) {
    return '$count matching places';
  }

  @override
  String mapSortHint(String origin) {
    return 'From $origin · walking times are estimated from straight-line distance';
  }

  @override
  String get mapRecenter => 'Go to starting point';

  @override
  String get profileAvatarEdit => 'Customize';

  @override
  String get profileAvatarSheetTitle => 'Choose a profile picture';

  @override
  String get profileAvatarSheetSubtitle => 'Pick a mascot';

  @override
  String get profileAvatarConfirm => 'Done';

  @override
  String get profileAvatarSaveFailed =>
      'Couldn\'t save your profile picture. Please try again.';

  @override
  String profileAvatarOption(int n) {
    return 'Mascot $n';
  }

  @override
  String get profileAvatarChange => 'Change profile picture';

  @override
  String get homeSearchFieldHint => 'Search restaurants, menus, categories';

  @override
  String get homeRecommendButton => 'Get today\'s pick';

  @override
  String get homeTodayPicksTitle => 'Today\'s picks';

  @override
  String get homeFilterBudget => 'Budget';

  @override
  String get homeFilterDistance => 'Distance';

  @override
  String get homeFilterParty => 'Party';

  @override
  String get homeFilterPurpose => 'Purpose';

  @override
  String get homeFilterSort => 'Sort';

  @override
  String get navMissions => 'Missions';

  @override
  String get missionPageTitle => 'Missions';

  @override
  String get missionTabMonthlyFallback => 'This month';

  @override
  String get missionTabDaily => 'Daily';

  @override
  String get missionTabWeekly => 'Weekly';

  @override
  String get missionTabChallenge => 'Challenges';

  @override
  String get missionCompletedLabel => 'Missions completed';

  @override
  String get missionProgressLabel => 'This month\'s progress';

  @override
  String get missionPointsMonth => 'Points earned this month';

  @override
  String get missionBadgePreview => 'Monthly badge';

  @override
  String missionBadgeLockedHint(int count) {
    return 'Complete $count missions to unlock it';
  }

  @override
  String get missionBadgeUnlocked => 'Unlocked';

  @override
  String get missionDone => 'Done';

  @override
  String get missionBadgeReward => 'Limited badge';

  @override
  String get missionExpired => 'Ended';

  @override
  String get missionUpcoming => 'Upcoming';

  @override
  String get missionDetailRequirement => 'How to complete';

  @override
  String get missionDetailProgress => 'Progress';

  @override
  String get missionDetailReward => 'Reward';

  @override
  String get missionDetailPeriod => 'Period';

  @override
  String get missionResetsDaily => 'Resets every day at 00:00 (Korea time)';

  @override
  String get missionResetsWeekly => 'Resets every Monday at 00:00 (Korea time)';

  @override
  String missionUntil(String date) {
    return 'Until $date';
  }

  @override
  String get missionAlwaysOn => 'Always on';

  @override
  String get missionActionRecommend => 'Get a pick';

  @override
  String get missionActionMap => 'Find places';

  @override
  String get missionActionFavorites => 'Find cheap places';

  @override
  String get missionActionCategories => 'Browse categories';

  @override
  String get missionActionReview => 'Write a review';

  @override
  String get missionActionPhoto => 'Upload a menu photo';

  @override
  String get missionActionCorrect => 'Suggest a correction';

  @override
  String get missionActionSoon =>
      'This isn\'t available yet. Once it opens, it counts toward the mission right away.';

  @override
  String get missionCelebrationTitle => 'Mission complete!';

  @override
  String missionCelebrationPoints(int points) {
    return '+${points}P earned';
  }

  @override
  String get missionCelebrationBadge => 'Badge unlocked';

  @override
  String get missionGuestTitle => 'Sign in to join the missions';

  @override
  String get missionGuestBody =>
      'Progress builds as you save and explore places. Points and badges are kept on your account.';

  @override
  String get missionEmptyTitle => 'No missions right now';

  @override
  String get missionEmptyBody =>
      'New missions will appear here when they open.';

  @override
  String get missionLoadFailed => 'Couldn\'t load missions';

  @override
  String get missionMyBadges => 'My badges';

  @override
  String get missionBadgesNone =>
      'No badges yet. Complete a mission to earn one.';

  @override
  String get missionBadgesAll => 'See all';

  @override
  String get missionBadgeCollectionTitle => 'Badge collection';

  @override
  String get missionTotalPoints => 'Total points';

  @override
  String missionBadgeCount(int count) {
    return '$count';
  }

  @override
  String get mealSoldOut => 'Sold out';

  @override
  String get mealSoldOutHint => 'Today\'s portions have all been sold.';

  @override
  String get mealServedWith => 'Served with';

  @override
  String get mealOrigin => 'Ingredient origin';

  @override
  String get homeMealChipTomorrowMenu => 'Tomorrow';

  @override
  String get footerAboutTitle => 'About 먹어보조';

  @override
  String get footerAboutBody =>
      '먹어보조 helps university students explore nearby restaurants, campus cafeteria meals and food-related community information in one place.';

  @override
  String get footerNoticesTitle => 'Announcements';

  @override
  String get footerNoticesEmpty => 'No announcements yet.';

  @override
  String get footerContactTitle => 'Questions & suggestions';

  @override
  String get footerContactBody =>
      'Send us a question or a suggestion about the service.';

  @override
  String get footerFeedback => 'Send feedback';

  @override
  String get footerContactNotReady => 'The contact channel is not set up yet.';

  @override
  String get footerServiceTitle => 'Service';

  @override
  String footerUniversities(int count) {
    return '$count universities supported';
  }

  @override
  String get footerServiceNote =>
      'Restaurant, cafeteria and mission information shows only verified data and what the operators publish.';

  @override
  String get footerAboutLink => 'About';

  @override
  String get homeFiltersApplied => 'Applied filters';

  @override
  String homeFilterRemove(String label) {
    return 'Remove $label';
  }

  @override
  String get homeFilterOpenAny => 'Including closed places';

  @override
  String get homeFiltersAdvancedTitle => 'Advanced filters';

  @override
  String get homeFiltersHide => 'Collapse';

  @override
  String get detailTitle => 'Restaurant info';

  @override
  String detailPhotoCount(int count) {
    return '$count photos';
  }

  @override
  String detailRatingLine(String avg, int count) {
    return '$avg · $count reviews';
  }

  @override
  String get detailNoReviews => 'No reviews yet';

  @override
  String detailOrderOpen(String time) {
    return 'Taking orders · last order $time';
  }

  @override
  String detailOrderSoon(String time) {
    return 'Last order soon · $time';
  }

  @override
  String detailOrderTooLate(String time) {
    return 'Last order $time, before you arrive';
  }

  @override
  String detailPriceFrom(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return 'From ₩$priceString per person';
  }

  @override
  String get detailInfoLocation => 'Location';

  @override
  String get detailInfoRoute => 'Getting there';

  @override
  String get detailInfoPhone => 'Phone';

  @override
  String get detailInfoAmenities => 'Amenities';

  @override
  String detailRoute(String origin, int minutes, String distance) {
    return 'About $minutes min on foot from $origin · about $distance';
  }

  @override
  String get detailRouteChange => 'Change start';

  @override
  String get detailRouteNote =>
      'Estimated from the straight-line distance. Check the real route in directions.';

  @override
  String get detailAmenitiesNone => 'Nothing confirmed yet';

  @override
  String get detailMap => 'Map';

  @override
  String detailDirectionsWalk(int minutes) {
    return 'Directions · $minutes min walk';
  }

  @override
  String get detailShowOnMap => 'Show on map';

  @override
  String get detailPhotoUploadSub => 'Shown on this page after review';

  @override
  String reviewsCount(int count) {
    return '$count reviews';
  }

  @override
  String reviewsStarLabel(int n) {
    return '$n★';
  }

  @override
  String get searchRecentTitle => 'Recent searches';

  @override
  String get searchRecentEmpty => 'No recent searches yet';

  @override
  String get searchRecentClear => 'Clear';

  @override
  String get searchSuggestTitle => 'How about these?';

  @override
  String searchResultsLine(String query, int total, int inside) {
    return '‘$query’: $total places · $inside match your conditions';
  }

  @override
  String get searchOutsideTitle => 'Outside your conditions · tap to open';

  @override
  String savedCountLine(int count) {
    return '$count saved';
  }

  @override
  String get savedGoRecommend => 'See recommendations';

  @override
  String authHeroTitle(String campus) {
    return 'Places near $campus,\npicked for your taste';
  }

  @override
  String get authHeroSubtitle =>
      'Recommendations work without an account.\nSign in when you want to write reviews or posts.';

  @override
  String get authWebStartTitle => 'Get started';

  @override
  String get authWebStartSubtitle =>
      'Recommendations work without an account. You only need one to write.';

  @override
  String get authWebPanelBody =>
      'Signed in, you can write reviews and posts, and your taste and saved places follow you to other devices.';
}
