// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get commonRetry => '重试';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonLater => '以后再说';

  @override
  String get commonSave => '保存';

  @override
  String get tryAgainLater => '请稍后再试。';

  @override
  String get mascotSemantics => '먹어보조 吉祥物';

  @override
  String get errPermissionDenied => '没有执行此操作的权限。请重新登录后再试。';

  @override
  String get navHome => '首页';

  @override
  String get navCommunity => '美食交流';

  @override
  String get navMap => '地图';

  @override
  String get navRecords => '记录';

  @override
  String get navProfile => '我的';

  @override
  String get languageSheetTitle => '语言设置';

  @override
  String get languageButtonTooltip => '语言设置';

  @override
  String get profileLanguage => '语言设置';

  @override
  String homeHeroAround(String university) {
    return '$university周边';
  }

  @override
  String get homeHeroTitle => '今天吃什么，\n一起来找找吧？';

  @override
  String get homeHeroSubtitle => '美味的一餐正在等着你！';

  @override
  String get homeSearchLabel => '搜索';

  @override
  String get searchHint => '搜索菜品、餐厅、关键词';

  @override
  String get homeNotificationsLabel => '通知';

  @override
  String get homeNotificationsSoon => '通知功能正在准备中。';

  @override
  String get homeMore => '查看更多 >';

  @override
  String get homeNearbyTitle => '校园周边美食';

  @override
  String get homeMenuTitle => '按菜品浏览';

  @override
  String get homeBannerLabel => '今日一餐推荐';

  @override
  String get homeBannerTitle => '今天吃这个怎么样？';

  @override
  String get homeBannerSubtitle => '来看看现在热门的餐厅吧！';

  @override
  String get homeBannerCta => '查看推荐';

  @override
  String get categoryAll => '全部';

  @override
  String get categoryKorean => '韩餐';

  @override
  String get categoryWestern => '西餐';

  @override
  String get categoryChinese => '中餐';

  @override
  String get categoryJapanese => '日料';

  @override
  String get categoryCafeDessert => '咖啡甜点';

  @override
  String get categorySnack => '小吃';

  @override
  String get categoryEtc => '其他';

  @override
  String get menuMalatang => '麻辣烫';

  @override
  String get menuPorkCutlet => '炸猪排';

  @override
  String get menuNaengmyeon => '冷面';

  @override
  String get menuSoondubu => '嫩豆腐汤';

  @override
  String get menuChicken => '炸鸡';

  @override
  String get menuTteokbokki => '炒年糕';

  @override
  String get menuPasta => '意大利面';

  @override
  String get menuAmericano => '美式咖啡';

  @override
  String get restaurantLoadFailedTitle => '无法加载餐厅';

  @override
  String get restaurantLoadFailedMessage => '无法加载餐厅信息。';

  @override
  String get restaurantEmptyTitle => '暂时没有找到附近的餐厅';

  @override
  String get universityChange => '更换学校';

  @override
  String restaurantListSubtitle(String university, String category) {
    return '$university · $category · 由近到远';
  }

  @override
  String restaurantTagDistance(String tag, String distance) {
    return '$tag · 距学校 $distance';
  }

  @override
  String restaurantDistanceFromSchool(String distance) {
    return '距学校 $distance';
  }

  @override
  String restaurantDistanceStraight(String distance) {
    return '距学校 $distance（直线距离）';
  }

  @override
  String get restaurantNoAddress => '暂无地址信息';

  @override
  String get restaurantNoPhone => '暂无电话号码';

  @override
  String get restaurantDataNotice => '暂不提供照片、评分、菜单、价格和营业时间。详细信息请在 Kakao 地图中查看。';

  @override
  String get restaurantOpenKakaoMap => '在 Kakao 地图中查看';

  @override
  String get restaurantLinkOpenFailed => '无法打开该链接。';

  @override
  String get restaurantErrNetwork => '请检查网络连接。';

  @override
  String get restaurantErrTimeout => '响应时间过长，请稍后再试。';

  @override
  String get restaurantErrQuota => '请求过多，请稍后再试。';

  @override
  String get restaurantErrAuth => '餐厅搜索服务器验证失败。';

  @override
  String get restaurantErrInvalid => '搜索条件无效。';

  @override
  String get restaurantErrUpstream => '获取餐厅信息时服务器出现问题。';

  @override
  String get restaurantErrUnknown => '发生未知错误。';

  @override
  String get searchIdleTitle => '想吃点什么？';

  @override
  String searchIdleMessage(String university) {
    return '我们会在$university周边为你搜索。';
  }

  @override
  String searchNoResultsTitle(String query) {
    return '没有“$query”的搜索结果';
  }

  @override
  String get searchNoResultsMessage => '试试其他关键词或更换学校。';

  @override
  String searchResultsSummary(String university, int count) {
    return '$university周边 · 由近到远 · $count 家';
  }

  @override
  String mapStatusLoading(String university) {
    return '$university · 正在加载餐厅…';
  }

  @override
  String mapStatusError(String university) {
    return '$university · 无法加载餐厅';
  }

  @override
  String mapStatusCount(String university, int count) {
    return '$university · 附近 $count 家';
  }

  @override
  String get mapErrorTitle => '无法加载地图';

  @override
  String get mapErrorMessage => '请稍后再试。餐厅列表和搜索仍可使用。';

  @override
  String get universitySelect => '选择学校';

  @override
  String universitySelectCurrent(String name) {
    return '选择学校，当前为$name';
  }

  @override
  String get universitySearchHint => '搜索学校名称';

  @override
  String get universityLoadFailed => '无法加载学校列表';

  @override
  String get universityNoMatch => '没有匹配的学校';

  @override
  String get universityFallbackName => '学校';

  @override
  String get cityAsan => '牙山';

  @override
  String get cityCheonan => '天安';

  @override
  String get favoriteAdd => '加入收藏';

  @override
  String get favoriteRemove => '取消收藏';

  @override
  String get favoriteSaveFailed => '无法保存收藏，请稍后再试。';

  @override
  String get recordsEmptyTitle => '还没有记录';

  @override
  String get recordsEmptyMessage => '记录所吃美食的功能正在准备中。';

  @override
  String get communityTitle => '美食交流即将上线';

  @override
  String get communityMessage => '我们正在努力开发，\n让你和同校的朋友聊聊美食！';

  @override
  String recommendStrategyProximity(String university) {
    return '离$university由近到远';
  }

  @override
  String get recommendExplainBaseline =>
      '目前还没有人气和口味数据，所以先按离学校的距离展示餐厅。个性化推荐正在准备中。';

  @override
  String get recommendStrategyPreferences => '按我的条件筛选';

  @override
  String recommendExplainPreferences(int count, int total) {
    return '已应用你保存的距离和菜系条件：在 $total 家中显示 $count 家，由近到远。预算、同行人和口味标签暂未生效，距离为直线距离的估算值。个性化推荐正在准备中。';
  }

  @override
  String get recommendNoMatchTitle => '没有符合条件的餐厅';

  @override
  String get recommendNoMatchMessage => '试试调整距离或菜系条件。';

  @override
  String get profileGuestTitle => '登录后收藏你喜欢的餐厅';

  @override
  String get profileGuestSubtitle => '无需登录也可以浏览和搜索。';

  @override
  String get profileLoginButton => '登录 / 注册';

  @override
  String profileGreeting(String nickname) {
    return '你好，$nickname';
  }

  @override
  String get profileGreetingSub => '今天也来找一顿美味的饭吧？';

  @override
  String get profileEditProfile => '编辑资料 →';

  @override
  String profileCampusHint(String city) {
    return '$city · 点击更换学校';
  }

  @override
  String get profileCampusHintNoCity => '点击更换学校';

  @override
  String get profileStatSaved => '收藏餐厅';

  @override
  String get profileStatRecords => '我的记录';

  @override
  String get profileStatPlans => '即将到来的饭约';

  @override
  String get profileStatUnavailable => '敬请期待';

  @override
  String get profileSaved => '收藏的餐厅';

  @override
  String profileSavedCount(int count) {
    return '$count 家';
  }

  @override
  String get profileRecords => '我的记录';

  @override
  String get profilePreferences => '我的口味设置';

  @override
  String get profileAccount => '账号设置';

  @override
  String get profileLogout => '退出登录';

  @override
  String get profileDefaultNickname => '먹어보조 用户';

  @override
  String get savedLoadFailed => '无法加载收藏的餐厅';

  @override
  String get savedEmptyTitle => '还没有收藏的餐厅';

  @override
  String get savedEmptyMessage => '点击喜欢的餐厅上的爱心即可收藏。';

  @override
  String savedCount(int count) {
    return '收藏的餐厅 $count 家';
  }

  @override
  String savedHiddenNote(int count) {
    return '有 $count 家不在当前所选学校的周边结果中，无法显示详情。选择对应学校后即可查看。';
  }

  @override
  String get accountNickname => '昵称';

  @override
  String get accountNicknameEdit => '修改昵称';

  @override
  String get accountEmail => '邮箱';

  @override
  String get accountLoginMethod => '登录方式';

  @override
  String get accountProviderKakao => 'Kakao';

  @override
  String get accountProviderEmail => '邮箱';

  @override
  String get authWelcomeTitle => '欢迎来到 먹어보조！';

  @override
  String get authWelcomeSubtitle => '登录后，找到属于你的美食。';

  @override
  String get authContinueKakao => '使用 Kakao 继续';

  @override
  String get authEmailLogin => '使用邮箱登录';

  @override
  String get authEmailSignUp => '使用邮箱注册';

  @override
  String get authBrowseAsGuest => '无需登录，继续浏览 →';

  @override
  String get authKakaoWaiting => '正在通过 Kakao 登录…';

  @override
  String get legalTerms => '服务条款';

  @override
  String get legalPrivacy => '隐私政策';

  @override
  String get legalNotPublished => '该文件尚未发布。';

  @override
  String get legalOpenFailed => '无法打开链接。';

  @override
  String get authEmailLoginTitle => '使用邮箱登录';

  @override
  String get authEmailLabel => '邮箱';

  @override
  String get authPasswordLabel => '密码';

  @override
  String get authPasswordConfirmLabel => '确认密码';

  @override
  String get authNewPasswordLabel => '新密码';

  @override
  String get authPasswordShow => '显示密码';

  @override
  String get authPasswordHide => '隐藏密码';

  @override
  String get authLoginButton => '登录';

  @override
  String get authForgotPasswordLink => '忘记密码？';

  @override
  String get authNoAccountSignUp => '还没有账号？立即注册';

  @override
  String get authHaveAccountLogin => '已有账号？去登录';

  @override
  String get authSignUpTitle => '使用邮箱注册';

  @override
  String get authSignUpSubtitle => '用邮箱和密码创建账号，注册后需要验证邮箱。';

  @override
  String get authSignUpButton => '注册';

  @override
  String authPasswordRule(int min) {
    return '请至少输入 $min 位。';
  }

  @override
  String get authVerifyTitle => '请查收邮件';

  @override
  String authVerifyMessage(String email) {
    return '我们已向 $email 发送了验证邮件。点击邮件中的链接即可完成注册。';
  }

  @override
  String get authVerifyNotSignedIn => '完成验证前不会登录。';

  @override
  String get authVerifyResend => '重新发送验证邮件';

  @override
  String authVerifyResendIn(int seconds) {
    return '$seconds 秒后可重新发送';
  }

  @override
  String get authVerifyResent => '已重新发送验证邮件。';

  @override
  String get authVerifyBackToLogin => '返回登录';

  @override
  String get authForgotTitle => '找回密码';

  @override
  String get authForgotMessage => '输入注册邮箱，我们会发送重置密码的链接。';

  @override
  String get authForgotSend => '发送重置邮件';

  @override
  String get authForgotResend => '重新发送';

  @override
  String authForgotSent(String email) {
    return '如果 $email 已注册，我们已发送重置链接，请查收邮件。';
  }

  @override
  String get authResetTitle => '设置新密码';

  @override
  String get authResetMessage => '请输入新密码。';

  @override
  String get authResetButton => '修改密码';

  @override
  String get authResetSuccess => '密码已修改。';

  @override
  String get errEmailRequired => '请输入邮箱。';

  @override
  String get errEmailInvalid => '邮箱格式不正确。';

  @override
  String get errPasswordRequired => '请输入密码。';

  @override
  String errPasswordShort(int min) {
    return '密码至少需要 $min 位。';
  }

  @override
  String get errPasswordMismatch => '两次输入的密码不一致。';

  @override
  String get authErrInvalidCredentials => '邮箱或密码不正确。';

  @override
  String get authErrEmailNotConfirmed => '邮箱尚未验证，请点击邮件中的链接完成验证。';

  @override
  String get authErrEmailTaken => '该邮箱已注册，请直接登录。';

  @override
  String get authErrInvalidEmail => '邮箱格式不正确。';

  @override
  String get authErrWeakPassword => '密码强度太弱，请使用更长、更复杂的密码。';

  @override
  String get authErrSamePassword => '请使用与之前不同的密码。';

  @override
  String get authErrKakaoCancelled => '已取消 Kakao 登录。';

  @override
  String get authErrKakaoConfig => 'Kakao 登录配置出现问题。请稍后再试，如仍有问题请联系我们。';

  @override
  String get authErrDeepLinkMissing => '登录未完成。可能已取消，或应用未收到登录结果，请重试。';

  @override
  String get authErrSessionExpired => '登录已过期，请重新登录。';

  @override
  String get authErrLinkExpired => '链接已过期或已被使用，请重新申请。';

  @override
  String get authErrRateLimited => '请求过于频繁，请稍后再试。';

  @override
  String get authErrNetwork => '请检查网络连接后重试。';

  @override
  String get authErrTimeout => '响应超时，请稍后再试。';

  @override
  String get authErrPasswordReset => '重置密码失败，请重试。';

  @override
  String get authErrProfileLoad => '无法加载个人信息，请重试。';

  @override
  String get authErrUnknown => '出了点问题，请稍后再试。';

  @override
  String get nicknameSetupTitle => '我们该怎么称呼你？';

  @override
  String get nicknameSetupSubtitle => '请设置在 먹어보조 中使用的昵称。';

  @override
  String get nicknameLabel => '昵称';

  @override
  String get nicknameHint => '请输入昵称';

  @override
  String get nicknameNext => '下一步';

  @override
  String nicknameRule(int min, int max) {
    return '请输入 $min~$max 个字符。';
  }

  @override
  String get nicknameErrEmpty => '请输入昵称。';

  @override
  String nicknameErrTooShort(int min) {
    return '昵称至少需要 $min 个字符。';
  }

  @override
  String nicknameErrTooLong(int max) {
    return '昵称最多 $max 个字符。';
  }

  @override
  String get nicknameErrInvalidChars => '昵称包含无法使用的字符。';

  @override
  String get nicknameSaveFailed => '无法保存昵称，请重试。';

  @override
  String get nicknameUpdated => '昵称已更新。';

  @override
  String get homeCampusMeals => '校园食堂';

  @override
  String get mealPageTitle => '本周校园食堂';

  @override
  String get mealToday => '今天';

  @override
  String get mealPrevWeek => '上一周';

  @override
  String get mealNextWeek => '下一周';

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

    return '$dateString，$today';
  }

  @override
  String get mealBreakfast => '早餐';

  @override
  String get mealLunch => '午餐';

  @override
  String get mealDinner => '晚餐';

  @override
  String get mealSelectCafeteria => '选择食堂';

  @override
  String get mealKindStudent => '学生食堂';

  @override
  String get mealKindDormitory => '宿舍食堂';

  @override
  String get mealKindStaff => '教职工食堂';

  @override
  String get mealKindOther => '食堂';

  @override
  String mealCafeteriaNth(String kind, int number) {
    return '$kind $number';
  }

  @override
  String get mealEmptyTitle => '暂无已登记的食堂菜单。';

  @override
  String get mealNotCollectedWeek => '本周的食堂信息尚未登记。';

  @override
  String get mealNotCollectedHint => '确认官方信息后会显示在这里。';

  @override
  String get mealClosedTitle => '此时段不供餐';

  @override
  String get mealClosedHint => '已由来源确认。';

  @override
  String get mealNoMenuTitle => '暂未公布菜单';

  @override
  String get mealNoMenuHint => '来源确认未公布菜单。';

  @override
  String get mealNoCafeteria => '该学校的食堂信息尚未登记。';

  @override
  String get mealLoadFailed => '无法加载食堂信息';

  @override
  String get mealLoadFailedHint => '请检查网络连接后重试。';

  @override
  String mealPrice(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return '₩$priceString';
  }

  @override
  String mealServingTime(String start, String end) {
    return '供餐 $start – $end';
  }

  @override
  String get mealSource => '来源';

  @override
  String get mealOpenSource => '打开来源';

  @override
  String mealVerifiedAt(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '核实于 $dateString';
  }

  @override
  String get mealKindMain => '主菜';

  @override
  String get mealKindSide => '配菜';

  @override
  String get mealKindSoup => '汤';

  @override
  String get mealKindRice => '饭';

  @override
  String get settingsAccountTitle => '账号';

  @override
  String get settingsAppTitle => '应用设置';

  @override
  String get themeTitle => '外观主题';

  @override
  String get themeLight => '浅色模式';

  @override
  String get themeDark => '深色模式';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get categoryChicken => '炸鸡';

  @override
  String get categoryFastFood => '快餐';

  @override
  String get categoryGlobal => '世界美食';

  @override
  String get cuisineAll => '全部';

  @override
  String get cuisineVietnamese => '越南菜';

  @override
  String get cuisineThai => '泰国菜';

  @override
  String get cuisineIndian => '印度菜';

  @override
  String get cuisineMexican => '墨西哥菜';

  @override
  String get cuisineOther => '其他世界美食';

  @override
  String get categoryGlobalNote =>
      '仅显示 Kakao 归类为亚洲菜、墨西哥菜等的餐厅，按距离排序。我们不会根据店名猜测菜系，部分餐厅可能未列出。';

  @override
  String get cuisineEmptyHint => '我们只搜索附近的餐厅，这所学校周边可能没有，或超出搜索范围。试试其他菜系或学校。';

  @override
  String categoryHeading(String category) {
    return '$category餐厅';
  }

  @override
  String get categorySortDistance => '距离优先';

  @override
  String get categorySortName => '名称';

  @override
  String categoryResultCount(int count) {
    return '$count 家';
  }

  @override
  String get categoryEmptyTitle => '没有找到该类别的餐厅。';

  @override
  String get categoryEmptyHint => '我们只搜索附近的餐厅。试试其他类别或学校。';

  @override
  String get categoryResultsNote => '按距离显示 Kakao 搜索结果，可能不是全部餐厅。';

  @override
  String get categoryAllTitle => '全部分类';

  @override
  String get categoryOpenAll => '查看全部分类';

  @override
  String categoryLocation(String university, String city) {
    return '$university · $city';
  }

  @override
  String get authReasonFavorite => '登录后即可收藏餐厅';

  @override
  String get authReasonRecords => '登录后即可记录所吃美食';

  @override
  String get authReasonCommunity => '登录后即可在美食交流中发帖';

  @override
  String get authReasonProfile => '编辑个人资料需要登录';

  @override
  String get authPromptBody => '无需登录也可以浏览和搜索。';

  @override
  String get authPromptLogin => '登录';

  @override
  String get onbStepLabel => '第 1–4 步';

  @override
  String get onbTitle => '今天吃什么？';

  @override
  String get onbSubtitle => '来找找适合你的餐厅吧？';

  @override
  String get onbCampusLabel => '当前校区';

  @override
  String get onbBadgeRequired => '必选';

  @override
  String get onbBadgeOptional => '可选';

  @override
  String get onbBudgetTitle => '一餐预算';

  @override
  String get onbBudgetDesc => '所有金额均为每人。想在特别的日子多花一点时，请选择“以上”。';

  @override
  String onbBudgetMax(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '₩$amountString以下';
  }

  @override
  String onbBudgetMin(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '₩$amountString以上';
  }

  @override
  String get onbAny => '无所谓';

  @override
  String get onbNeedBudget => '请选择预算。';

  @override
  String get onbDistanceTitle => '愿意走多远？';

  @override
  String get onbDistanceDesc => '以校区为基准。时间是按直线距离换算的大致估算值。';

  @override
  String onbWalkMinutes(int minutes) {
    return '步行 $minutes 分钟';
  }

  @override
  String onbDriveMinutes(int minutes) {
    return '驾车 $minutes 分钟';
  }

  @override
  String get onbWalkLabel => '步行';

  @override
  String get onbDriveLabel => '驾车';

  @override
  String get onbNeedDistance => '请选择距离。';

  @override
  String get onbOriginTitle => '起点：校区中心';

  @override
  String get onbOriginHint => '暂无正门坐标，因此按校区中心点的直线距离计算。';

  @override
  String get onbCompanionTitle => '和谁一起吃？';

  @override
  String get onbCompanionDesc => '选择你平时和谁一起吃饭，可多选。';

  @override
  String get companionSolo => '一个人';

  @override
  String get companionFriends => '2~3 位朋友';

  @override
  String get companionGroup => '4 人以上';

  @override
  String get companionSenior => '和学长学姐';

  @override
  String get companionJunior => '和学弟学妹';

  @override
  String get companionProfessor => '和教授';

  @override
  String get onbFoodTitle => '喜欢的食物';

  @override
  String get onbFoodDesc => '可以多选，也可以跳过。';

  @override
  String get cuisineKorean => '韩餐';

  @override
  String get cuisineJapanese => '日料';

  @override
  String get cuisineChinese => '中餐';

  @override
  String get cuisineSnack => '小吃';

  @override
  String get cuisineCafe => '咖啡厅';

  @override
  String get cuisineWestern => '西餐';

  @override
  String get cuisineSalad => '沙拉';

  @override
  String get cuisineAny => '都可以';

  @override
  String get tagSpicy => '辣的';

  @override
  String get tagHearty => '管饱';

  @override
  String get tagValue => '性价比高';

  @override
  String get tagLight => '清淡';

  @override
  String get onbUntriedTitle => '优先推荐没吃过的';

  @override
  String get onbUntriedDesc => '根据记录把最近吃过的种类往后排。记录功能上线后生效。';

  @override
  String get onbFilterNote => '目前只有距离和菜系会影响结果。预算、同行人和口味标签先保存，待有价格和座位数据后再应用。';

  @override
  String onbCountLabel(int count) {
    return '当前条件下有 $count 家';
  }

  @override
  String get onbCountUnknown => '正在加载附近餐厅…';

  @override
  String get onbCountNote => '仅按距离和菜系';

  @override
  String get onbClearAll => '清除所选';

  @override
  String get onbRandom => '随机';

  @override
  String get onbViewRecs => '查看推荐';

  @override
  String onbViewRecsCount(int count) {
    return '查看 $count 家推荐';
  }

  @override
  String get onbSave => '保存';

  @override
  String get onbRandomNone => '没有符合条件的餐厅。';

  @override
  String get onbLogout => '退出登录';

  @override
  String get prefsEditTitle => '我的口味设置';

  @override
  String get prefsEditSubtitle => '可以修改已保存的条件。';

  @override
  String get prefsSaved => '已保存你的偏好。';

  @override
  String get prefsLoadFailed => '无法加载已保存的偏好';

  @override
  String get prefsSaveFailed => '保存失败。你的选择仍保留，请重试。';
}
