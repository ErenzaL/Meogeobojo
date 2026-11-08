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
  String get searchHint => 'Search dishes, restaurants, keywords';

  @override
  String get homeNotificationsLabel => 'Notifications';

  @override
  String get homeNotificationsSoon => 'Notifications are coming soon.';

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
  String savedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved restaurants',
      one: '1 saved restaurant',
    );
    return '$_temp0';
  }

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
  String get authWelcomeTitle => 'Welcome to 먹어보조!';

  @override
  String get authWelcomeSubtitle => 'Sign in to find your own favorite spots.';

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
  String get mealEmptyTitle => 'No campus meal menu has been registered.';

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
}
