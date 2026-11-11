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
  String get notificationsTitle => '通知';

  @override
  String get notificationsEmpty => '暂无新通知';

  @override
  String get notificationsEmptyHint => '有新消息时会显示在这里。';

  @override
  String get notificationsNew => '新';

  @override
  String get notificationsOpenLink => '查看详情';

  @override
  String notificationsBellUnread(int count) {
    return '通知，$count 条未读';
  }

  @override
  String get notificationsJustNow => '刚刚';

  @override
  String notificationsMinutesAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String notificationsHoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String notificationsDaysAgo(int n) {
    return '$n 天前';
  }

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
  String get mealEmptyTitle => '暂无登记的菜单信息。';

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

  @override
  String get homeTitle => '今天吃什么？';

  @override
  String homeSubtitle(String part, String time, String origin) {
    return '$part · $time · 从$origin出发';
  }

  @override
  String get dayPartBreakfast => '早餐';

  @override
  String get dayPartLunch => '午餐';

  @override
  String get dayPartDinner => '晚餐';

  @override
  String get dayPartLateNight => '夜宵';

  @override
  String get homeRestartTooltip => '重新开始';

  @override
  String get homeProfileTooltip => '个人资料';

  @override
  String homeOriginChip(String origin) {
    return '以$origin为准';
  }

  @override
  String get homeConditionsChip => '条件';

  @override
  String homeConditionsActive(int count) {
    return '已应用$count项条件';
  }

  @override
  String homeHeroRank(int total, int rank) {
    return '$total家中第$rank名';
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
    return '$count条评价';
  }

  @override
  String homeReasonCuisine(String cuisine) {
    return '$cuisine，正是你选的菜系';
  }

  @override
  String get homeReasonBudget => '在预算范围内';

  @override
  String get homeReasonClosest => '离你最近';

  @override
  String homeReasonWalk(int minutes) {
    return '步行$minutes分钟';
  }

  @override
  String get homeArrival => '预计到达';

  @override
  String get homeLastOrder => '最后点单';

  @override
  String homeWalkAbout(int minutes) {
    return '步行约$minutes分钟';
  }

  @override
  String homeSlackHM(int hours, int minutes) {
    return '还剩$hours小时$minutes分钟';
  }

  @override
  String homeSlackH(int hours) {
    return '还剩$hours小时';
  }

  @override
  String homeSlackM(int minutes) {
    return '还剩$minutes分钟';
  }

  @override
  String get homeNoInfo => '暂无信息';

  @override
  String get homeClosesBeforeArrival => '到达前就打烊了';

  @override
  String get homeDirections => '导航';

  @override
  String get homeInfo => '详情';

  @override
  String get homeAltTitle => '不喜欢的话';

  @override
  String get homePickForMe => '帮我选一个';

  @override
  String get homeNextPick => '下一个 ›';

  @override
  String get homePrevPick => '‹ 上一个';

  @override
  String get homeRestart => '重新开始';

  @override
  String get homePromptTitle => '先选好条件再看推荐';

  @override
  String get homePromptMessage => '选好预算、距离等条件，或点“获取今日推荐”。';

  @override
  String get homeGameButton => '玩游戏来选';

  @override
  String get homeGameTitle => '吃什么？玩游戏决定！';

  @override
  String get homeGameSub => '从符合当前条件的餐厅里选。';

  @override
  String get homeGameRoulette => '转盘';

  @override
  String get homeGameRouletteHint => '转到哪家去哪家';

  @override
  String get homeGameLadder => '爬梯子';

  @override
  String get homeGameLadderHint => '选一条线往下走';

  @override
  String get homeGameCards => '翻牌';

  @override
  String get homeGameCardsHint => '翻开哪张去哪家';

  @override
  String get homeGameSpin => '开转！';

  @override
  String get homeGameSpinning => '转动中…';

  @override
  String get homeGameLadderPrompt => '选一条线出发';

  @override
  String get homeGameCardsPrompt => '选一张牌';

  @override
  String get homeGameResult => '今天就去这家！';

  @override
  String get homeGameAgain => '再来一次';

  @override
  String get homeGameConfirm => '就这家';

  @override
  String get homeGameBack => '换个游戏';

  @override
  String homeGameChosen(String name) {
    return '已选定$name，请在最上面的推荐卡片查看。';
  }

  @override
  String homeCmpCloser(int minutes) {
    return '近$minutes分钟';
  }

  @override
  String homeCmpCheaper(int amount) {
    final intl.NumberFormat amountNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String amountString = amountNumberFormat.format(amount);

    return '便宜$amountString韩元';
  }

  @override
  String get homeCmpRating => '评分更高';

  @override
  String get homeCmpLater => '营业到更晚';

  @override
  String get homeStatusOrderable => '可点单';

  @override
  String homeStatusClosesAt(String time) {
    return '$time截止点单';
  }

  @override
  String homeSeeOnMap(int count) {
    return '在地图上查看符合条件的$count家';
  }

  @override
  String get homeEmptyTitle => '没有符合条件的店';

  @override
  String get homeEmptyMessage => '放宽一些条件会看到更多。';

  @override
  String get homeMealTitle => '今日食堂';

  @override
  String homeMealChipNow(String meal) {
    return '现在$meal';
  }

  @override
  String homeMealChipToday(String meal) {
    return '今天$meal';
  }

  @override
  String homeMealChipTomorrow(String meal) {
    return '明天$meal';
  }

  @override
  String get homeMealNone => '暂未登记近期的食堂菜单。';

  @override
  String homeMealAvgCaption(String place) {
    return '午餐均价 · 以$place步行15分钟内的餐厅为准';
  }

  @override
  String get homeMealBarCafeteria => '食堂';

  @override
  String get homeMealBarOutside => '校外餐厅';

  @override
  String get homeMealSavingPre => '每月在食堂吃20顿可省 ';

  @override
  String get homeMealSavingPost => '。';

  @override
  String get homeMealNoCompare => '价格数据还不足，需要食堂和校外餐厅的价格才能比较。';

  @override
  String get homeMealWeekly => '本周菜单';

  @override
  String get homeMealCompare => '对比校外餐厅';

  @override
  String get homeCompareSoon => '价格对比页面正在准备中。';

  @override
  String get originCampusCenter => '校园中心';

  @override
  String get originSheetTitle => '从哪里出发？';

  @override
  String get originSheetDesc => '地图和推荐会按从所选位置出发的步行距离重新排序。建筑位置仅为演示示例。';

  @override
  String get originGroupGates => '校门';

  @override
  String get originGroupColleges => '学院';

  @override
  String get originGroupBuildings => '主要建筑';

  @override
  String get originGroupPins => '我的标记';

  @override
  String get originNoPins => '还没有保存的标记。';

  @override
  String originNearest(String name, int minutes) {
    return '最近：$name · 步行$minutes分钟';
  }

  @override
  String get originNearestNone => '附近没有符合条件的店';

  @override
  String get originPickOnMap => '在地图上标记';

  @override
  String get originPinPickerTitle => '选择出发位置';

  @override
  String get originPinPickerHint => '移动地图，让标记对准想要的位置。';

  @override
  String get originPinConfirm => '就选这里';

  @override
  String get originPinNameTitle => '标记名称';

  @override
  String get originPinNameHint => '例如：宿舍门口';

  @override
  String originPinDefaultName(int number) {
    return '我的标记$number';
  }

  @override
  String get originPinDelete => '删除标记';

  @override
  String get originPinFailed => '无法获取位置，请重试。';

  @override
  String get condTitle => '条件';

  @override
  String get condSubtitle => '首页、地图、搜索通用。';

  @override
  String get condMust => '必须满足';

  @override
  String get condMustHint => '不符合的店会被排除';

  @override
  String get condMissingNote => '没有价格或营业信息的店不会被排除。';

  @override
  String get condChange => '更改';

  @override
  String get condOpenNow => '仅显示现在可点单的店';

  @override
  String get condOpenNowHint => '到达时尚未截止点单的店。仅在为之后做计划时关闭。';

  @override
  String get condCuisine => '菜系';

  @override
  String get condOps => '营业·便利';

  @override
  String get condAmenityNoBreak => '无休息时间';

  @override
  String get condAmenityParking => '可停车';

  @override
  String get condAmenityLocalCurrency => '地方货币（牙山Pay）';

  @override
  String get condAmenityFast => '翻台快';

  @override
  String get condAmenityTakeout => '可打包';

  @override
  String get condAmenityLate => '营业到晚上10点';

  @override
  String get condSoft => '影响推荐顺序';

  @override
  String get condParty => '几个人吃？';

  @override
  String get condPartyFew => '2~3人';

  @override
  String get condNeeds => '需要什么';

  @override
  String get condNeedQuiet => '安静聊天';

  @override
  String get condNeedQuick => '快速用餐';

  @override
  String get condNeedGenerous => '分量足';

  @override
  String get condUntried => '优先没去过的店';

  @override
  String condUntriedHint(int count) {
    return '已参考$count条用餐记录 · 按餐厅计算';
  }

  @override
  String get condSort => '排序';

  @override
  String get condSortRecommended => '推荐';

  @override
  String get condSortPrice => '价格';

  @override
  String get condSortRating => '评分';

  @override
  String get condSoftNote => '目前按距离推荐。人数和需求会在有数据后影响顺序。';

  @override
  String get condResetAll => '全部清除';

  @override
  String get condResetThis => '清除此项';

  @override
  String condShowCount(int count) {
    return '查看$count家';
  }

  @override
  String get condNoMatch => '没有符合条件的店';

  @override
  String get condRestart => '回到初始画面重新设置';

  @override
  String get condRestartTitle => '重新开始设置？';

  @override
  String get condRestartBody => '这会重置当前条件和出发位置，并重新打开口味设置。';

  @override
  String get condRestartAction => '重新设置';

  @override
  String get condRestartGuestDone => '已重置条件和出发位置。';

  @override
  String get restaurantAboutTitle => '简介';

  @override
  String get restaurantMenuTitle => '菜单';

  @override
  String get restaurantMenuSoldOut => '已售罄';

  @override
  String get authReasonContribute => '登录后才能发布评价和照片。';

  @override
  String get reviewsTitle => '评价';

  @override
  String reviewsSummary(String avg, int count) {
    return '平均 $avg · $count条';
  }

  @override
  String get reviewsEmpty => '还没有评价，来写第一条吧。';

  @override
  String get reviewWrite => '写评价';

  @override
  String get reviewEditMine => '修改我的评价';

  @override
  String get reviewMine => '我的评价';

  @override
  String get reviewAuthor => '学生';

  @override
  String get reviewEditorHint => '说说味道、价格、氛围（可选）';

  @override
  String get reviewRating => '评分';

  @override
  String get reviewSave => '保存';

  @override
  String get reviewDelete => '删除';

  @override
  String get reviewDeleteConfirm => '删除这条评价？';

  @override
  String get reviewSaved => '评价已保存。';

  @override
  String get reviewDeleted => '评价已删除。';

  @override
  String get reviewSaveFailed => '保存失败，请稍后再试。';

  @override
  String get reviewRatingRequired => '请选择评分。';

  @override
  String get reviewStatusVisible => '已公开';

  @override
  String get reviewStatusHidden => '已被管理员隐藏，其他同学看不到。';

  @override
  String get reviewStatusRemoved => '已被删除。';

  @override
  String get reportAction => '举报';

  @override
  String get reportTitle => '举报这条评价？';

  @override
  String get reportReasonAbuse => '辱骂或攻击';

  @override
  String get reportReasonSpam => '广告或垃圾信息';

  @override
  String get reportReasonFalse => '与事实不符';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportSend => '举报';

  @override
  String get reportSent => '已举报，管理员会查看。';

  @override
  String get reportAlready => '你已经举报过这条评价。';

  @override
  String get reportFailed => '举报失败，请稍后再试。';

  @override
  String get photoUploadButton => '上传照片';

  @override
  String get photoSheetTitle => '上传照片';

  @override
  String get photoKindRestaurant => '餐厅照片';

  @override
  String get photoKindMenu => '菜单照片';

  @override
  String get photoPick => '选择照片';

  @override
  String get photoChange => '换一张';

  @override
  String get photoCaptionHint => '照片说明（可选）';

  @override
  String get photoConsent => '同意审核通过后在먹어보조展示这张照片。';

  @override
  String get photoPrivateNote => '审核前只有你自己能看到。';

  @override
  String get photoSubmit => '提交';

  @override
  String get photoSubmitting => '上传中…';

  @override
  String get photoSubmitted => '已提交，管理员审核后公开。';

  @override
  String get photoTooLarge => '照片不能超过5MB。';

  @override
  String get photoFailed => '上传失败，请稍后再试。';

  @override
  String get photoDuplicate => '你已经提交过这张照片。';

  @override
  String get photoTooMany => '待审核的照片太多，请稍后再试。';

  @override
  String get myContribTitle => '我的评价和照片';

  @override
  String get myContribOpen => '查看我的评价和照片';

  @override
  String get myContribReviews => '我的评价';

  @override
  String get myContribPhotos => '我的照片';

  @override
  String get myContribEmpty => '你还没有发布评价或照片。';

  @override
  String get myContribLoadFailed => '加载失败。';

  @override
  String get contribStatusPending => '审核中';

  @override
  String get contribStatusApproved => '已公开';

  @override
  String get contribStatusRejected => '未通过';

  @override
  String contribRejectedReason(String reason) {
    return '原因：$reason';
  }

  @override
  String get contribWithdraw => '撤回';

  @override
  String get contribWithdrawConfirm => '撤回提交？照片也会被删除。';

  @override
  String get contribWithdrawn => '已撤回。';

  @override
  String get missionActionPickPlace => '选一家餐厅，在详情页留下评价或照片，会立即计入任务。';

  @override
  String get restaurantGalleryTitle => '照片';

  @override
  String get restaurantMenuRecommended => '推荐';

  @override
  String restaurantPriceWon(int price) {
    final intl.NumberFormat priceNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String priceString = priceNumberFormat.format(price);

    return '$priceString韩元';
  }

  @override
  String get mealBreakfastProgram => '早餐 · 千元早餐';

  @override
  String mealHeading(String day, String meal) {
    return '$day$meal食堂';
  }

  @override
  String get mealDayTomorrow => '明天';

  @override
  String get myTitle => '我的主页';

  @override
  String get myConditionsTitle => '我的条件';

  @override
  String get myConditionsEmpty => '还没有选择条件。先从预算和距离开始吧。';

  @override
  String get myRestart => '重新设置';

  @override
  String myOriginHint(int count) {
    return '距离基准位置 · 已保存$count个标记';
  }

  @override
  String get myActivityTitle => '我的活动';

  @override
  String get recordsPageTitle => '我的记录';

  @override
  String get recordsSubtitle => '只有你能看到的美食日记';

  @override
  String get recordsAdd => '添加记录';

  @override
  String recordsReportTitle(int month) {
    return '$month月报告';
  }

  @override
  String get recordsReportBasis => '以本月记录为准';

  @override
  String get recordsStatMeals => '外出就餐';

  @override
  String get recordsStatSpend => '餐费合计';

  @override
  String get recordsStatAvg => '每餐均价';

  @override
  String get recordsReportHint => '记录你吃过的地方，我们会整理本月餐费和常去的店。';

  @override
  String recordsTabEaten(String count) {
    return '吃过 $count';
  }

  @override
  String recordsTabWant(String count) {
    return '想去 $count';
  }

  @override
  String get recordsNoRecordsTitle => '还没有记录';

  @override
  String get recordsNoRecordsBody => '记录地点、菜品、金额和同行的人，就能形成你的美食日记。';

  @override
  String get recordsFirst => '添加第一条记录';

  @override
  String communitySubtitle(String campus) {
    return '$campus学生社区';
  }

  @override
  String get communityMyActivity => '我的活动';

  @override
  String get communityFilterAll => '全部';

  @override
  String get communityFilterReviews => '餐厅评价';

  @override
  String get communityFilterMeets => '一起吃';

  @override
  String get communityFilterQuestions => '提问';

  @override
  String get communityComposerTitle => '分享一下今天吃的菜吧？';

  @override
  String get communityWriteReview => '写评价';

  @override
  String get communityStartMeet => '发起一起吃';

  @override
  String get communityAsk => '提问';

  @override
  String get communityFeedTitle => '校园周边';

  @override
  String get communitySortLatest => '最新';

  @override
  String get communityEmptyTitle => '还没有帖子';

  @override
  String get communityEmptyBody => '发布今天吃的菜，或找人一起吃吧。';

  @override
  String get communityComposeSoon => '美食交流发帖功能正在准备中。';

  @override
  String get mapPageTitle => '周边餐厅';

  @override
  String get mapOpenNowChip => '现在可点单';

  @override
  String mapMatchCount(int count) {
    return '符合条件的$count家';
  }

  @override
  String mapSortHint(String origin) {
    return '以$origin为准 · 步行时间按直线距离估算';
  }

  @override
  String get mapRecenter => '回到出发位置';

  @override
  String get profileAvatarEdit => '装扮';

  @override
  String get profileAvatarSheetTitle => '选择头像';

  @override
  String get profileAvatarSheetSubtitle => '从吉祥物中选择';

  @override
  String get profileAvatarConfirm => '选择完成';

  @override
  String get profileAvatarSaveFailed => '无法保存头像，请重试。';

  @override
  String profileAvatarOption(int n) {
    return '吉祥物 $n';
  }

  @override
  String get profileAvatarChange => '更换头像';

  @override
  String get homeSearchFieldHint => '搜索餐厅、菜单、类别';

  @override
  String get homeRecommendButton => '获取今日推荐';

  @override
  String get homeTodayPicksTitle => '今日推荐';

  @override
  String get homeFilterBudget => '预算';

  @override
  String get homeFilterDistance => '距离';

  @override
  String get homeFilterParty => '人数';

  @override
  String get homeFilterPurpose => '用途';

  @override
  String get homeFilterSort => '排序';

  @override
  String get navMissions => '任务';

  @override
  String get missionPageTitle => '任务';

  @override
  String get missionTabMonthlyFallback => '本月任务';

  @override
  String get missionTabDaily => '每日';

  @override
  String get missionTabWeekly => '每周';

  @override
  String get missionTabChallenge => '挑战';

  @override
  String get missionCompletedLabel => '已完成任务';

  @override
  String get missionProgressLabel => '本月进度';

  @override
  String get missionPointsMonth => '本月获得积分';

  @override
  String get missionBadgePreview => '本月徽章';

  @override
  String missionBadgeLockedHint(int count) {
    return '完成 $count 个任务即可获得';
  }

  @override
  String get missionBadgeUnlocked => '已获得';

  @override
  String get missionDone => '完成';

  @override
  String get missionBadgeReward => '限定徽章';

  @override
  String get missionExpired => '已结束';

  @override
  String get missionUpcoming => '即将开始';

  @override
  String get missionDetailRequirement => '完成条件';

  @override
  String get missionDetailProgress => '进度';

  @override
  String get missionDetailReward => '奖励';

  @override
  String get missionDetailPeriod => '期间';

  @override
  String get missionResetsDaily => '每天 0 点（韩国时间）重新开始';

  @override
  String get missionResetsWeekly => '每周一 0 点（韩国时间）重新开始';

  @override
  String missionUntil(String date) {
    return '截至 $date';
  }

  @override
  String get missionAlwaysOn => '长期进行';

  @override
  String get missionActionRecommend => '获取推荐';

  @override
  String get missionActionMap => '去找餐厅';

  @override
  String get missionActionFavorites => '找实惠的餐厅';

  @override
  String get missionActionCategories => '浏览分类';

  @override
  String get missionActionReview => '写评价';

  @override
  String get missionActionPhoto => '上传菜单照片';

  @override
  String get missionActionCorrect => '提交信息修改';

  @override
  String get missionActionSoon => '该功能尚未开放，开放后会立即计入任务。';

  @override
  String get missionCelebrationTitle => '任务完成！';

  @override
  String missionCelebrationPoints(int points) {
    return '获得 +${points}P';
  }

  @override
  String get missionCelebrationBadge => '获得徽章';

  @override
  String get missionGuestTitle => '登录后参与任务';

  @override
  String get missionGuestBody => '收藏和浏览餐厅时进度会不断累积。积分和徽章保存在您的账号中。';

  @override
  String get missionEmptyTitle => '暂无进行中的任务';

  @override
  String get missionEmptyBody => '新任务开放后会显示在这里。';

  @override
  String get missionLoadFailed => '无法加载任务';

  @override
  String get missionMyBadges => '我的徽章';

  @override
  String get missionBadgesNone => '还没有徽章。完成任务来获得吧。';

  @override
  String get missionBadgesAll => '查看全部';

  @override
  String get missionBadgeCollectionTitle => '徽章收藏';

  @override
  String get missionTotalPoints => '累计积分';

  @override
  String missionBadgeCount(int count) {
    return '$count';
  }

  @override
  String get mealSoldOut => '已售罄';

  @override
  String get mealSoldOutHint => '今天准备的份数已全部售完。';

  @override
  String get mealServedWith => '配餐';

  @override
  String get mealOrigin => '原产地标示';

  @override
  String get homeMealChipTomorrowMenu => '明天';

  @override
  String get footerAboutTitle => '关于 먹어보조';

  @override
  String get footerAboutBody => '먹어보조 帮助大学生在一个地方了解学校周边餐厅、学食和与美食相关的社区信息。';

  @override
  String get footerNoticesTitle => '公告';

  @override
  String get footerNoticesEmpty => '暂无公告。';

  @override
  String get footerContactTitle => '咨询与建议';

  @override
  String get footerContactBody => '欢迎留下对服务的疑问或建议。';

  @override
  String get footerFeedback => '发送意见';

  @override
  String get footerContactNotReady => '咨询渠道尚在准备中。';

  @override
  String get footerServiceTitle => '服务信息';

  @override
  String footerUniversities(int count) {
    return '支持 $count 所大学';
  }

  @override
  String get footerServiceNote => '餐厅、学食和任务信息仅显示已核实的资料和运营者发布的内容。';

  @override
  String get footerAboutLink => '服务介绍';

  @override
  String get homeFiltersApplied => '已应用的条件';

  @override
  String homeFilterRemove(String label) {
    return '移除 $label';
  }

  @override
  String get homeFilterOpenAny => '包含已打烊的店';

  @override
  String get homeFiltersAdvancedTitle => '高级筛选';

  @override
  String get homeFiltersHide => '收起';
}
