// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'ZAMEL';

  @override
  String get loginTitle => 'تسجيل الدخول إلى حسابك';

  @override
  String get loginSubtitle => 'مرحباً بك من جديد';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get forgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get loginButton => 'تسجيل الدخول';

  @override
  String get loginInvalidEmail => 'الرجاء إدخال بريد إلكتروني صحيح';

  @override
  String get loginInvalidPassword =>
      'الرجاء إدخال كلمة مرور صحيحة (٦ أحرف على الأقل)';

  @override
  String get loginResetPasswordTitle => 'استعادة كلمة المرور';

  @override
  String get loginResetPasswordHint => 'أدخل بريدك المسجل لدينا';

  @override
  String get loginResetPasswordCancel => 'إلغاء';

  @override
  String get loginResetPasswordSend => 'إرسال الرابط';

  @override
  String get loginResetPasswordSuccess =>
      '✅ تم إرسال رابط استعادة كلمة المرور إلى بريدك.';

  @override
  String get loginSignUpPrompt => 'ليس لديك حساب؟ سجّل الآن';

  @override
  String get registerTitle => 'تسجيل حساب جديد';

  @override
  String get usernameLabel => 'اسم المستخدم';

  @override
  String get confirmPasswordLabel => 'تأكيد كلمة المرور';

  @override
  String get createAccountButton => 'إنشاء الحساب';

  @override
  String get registerInvalidUsername =>
      '⚠️ اسم المستخدم يجب أن يكون ٣ أحرف على الأقل';

  @override
  String get registerInvalidEmail => '⚠️ الرجاء إدخال بريد إلكتروني صالح';

  @override
  String get registerInvalidPassword =>
      '⚠️ كلمة المرور يجب أن تكون ٦ أحرف على الأقل';

  @override
  String get registerPasswordMismatch => '⚠️ كلمة المرور وتأكيدها غير متطابقين';

  @override
  String get registerAlreadyHaveAccount => 'لديك حساب بالفعل؟ تسجيل الدخول';

  @override
  String get registerSuccessTitle => 'تأكيد الحساب';

  @override
  String get registerSuccessContent =>
      'تم إنشاء حسابك بنجاح! أرسلنا رابط تفعيل إلى بريدك الإلكتروني.';

  @override
  String get registerSuccessButton => 'حسناً، فهمت';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsInterface => 'الواجهة';

  @override
  String get settingsDarkMode => 'الوضع الداكن';

  @override
  String get settingsDarkModeSubtitle => 'واجهة مريحة للليل أو النهار';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsLanguageSubtitle => 'اختر لغتك المفضلة';

  @override
  String get settingsCustomMode => 'الوضع المخصص';

  @override
  String get settingsCustomModeSubtitle =>
      'إخفاء العناصر غير الضرورية وتبسيط الشاشة';

  @override
  String get settingsNotifications => 'الإشعارات والتحديث';

  @override
  String get settingsSoundNotifications => 'التنبيهات الصوتية';

  @override
  String get settingsSoundNotificationsSubtitle =>
      'تنبيهات واضحة عند الرسائل والمكالمات';

  @override
  String get settingsAutoRefresh => 'التحديث التلقائي للمنشورات';

  @override
  String get settingsAutoRefreshSubtitle => 'تحديث مستمر للمنشورات الجديدة';

  @override
  String get settingsPresence => 'إظهار حالة الاتصال';

  @override
  String get settingsPresenceSubtitle =>
      'عرض متصل الآن وآخر ظهور في الدردشات والمحادثات';

  @override
  String get settingsCompactMode => 'التخطيط المدمج';

  @override
  String get settingsCompactModeSubtitle =>
      'تقليل المسافات والعناصر لعرض أكثر سلاسة';

  @override
  String get settingsGlobalTitle => 'التطبيق عالمي';

  @override
  String get settingsGlobalSubtitle =>
      'يدعم لغات متعددة ويوفر تجربة مناسبة للمستخدمين حول العالم.';

  @override
  String get settingsResetTitle => 'إعادة تعيين الإعدادات';

  @override
  String get settingsResetSubtitle =>
      'استعادة القيم الافتراضية لجميع الخيارات.';

  @override
  String get settingsResetSuccess => 'تمت إعادة تعيين الإعدادات بنجاح';

  @override
  String get settingsAboutTitle => 'عن التطبيق';

  @override
  String get settingsAboutSubtitle =>
      'ZAMEL نسخة مخصصة من التطبيق السابق مع دعم Firebase وميزات عالمية.';

  @override
  String get adminTitle => 'لوحة الإدارة';

  @override
  String get adminLoginRequired =>
      'الرجاء تسجيل الدخول للوصول إلى لوحة الإدارة.';

  @override
  String get adminRoleRequired => 'عذراً، هذه الصفحة متاحة للمشرفين فقط.';

  @override
  String get adminUsersTab => 'المستخدمون';

  @override
  String get adminPostsTab => 'المنشورات';

  @override
  String get adminStoriesTab => 'القصص';

  @override
  String adminErrorUsers(Object error) {
    return 'حدث خطأ في جلب المستخدمين: $error';
  }

  @override
  String get adminNoUsers => 'لا يوجد مستخدمين حتى الآن.';

  @override
  String adminFollowers(Object count) {
    return 'متابعين $count';
  }

  @override
  String adminPoints(Object points) {
    return 'نقاط $points';
  }

  @override
  String get adminBlockedFromPosting => 'ممنوع من النشر';

  @override
  String get adminBanned => 'محظور';

  @override
  String get adminUnbanUser => 'رفع الحظر';

  @override
  String get adminBanUser => 'حظر المستخدم';

  @override
  String get adminDisablePosting => 'تعطيل النشر';

  @override
  String get adminEnablePosting => 'تفعيل النشر';

  @override
  String get adminUpgrade => 'ترقية';

  @override
  String get adminDowngrade => 'خفض رتبة';

  @override
  String get adminUserBanSuccess => 'تم حظر المستخدم';

  @override
  String get adminUserUnbanSuccess => 'تم رفع الحظر عن المستخدم';

  @override
  String get adminPostingEnabled => 'تم تفعيل النشر للمستخدم';

  @override
  String get adminPostingDisabled => 'تم تعطيل النشر عن المستخدم';

  @override
  String get adminPromoted => 'تم ترقية المستخدم إلى مشرف';

  @override
  String get adminDemoted => 'تم خفض المستخدم إلى مستخدم عادي';

  @override
  String adminErrorPosts(Object error) {
    return 'حدث خطأ في جلب المنشورات: $error';
  }

  @override
  String get adminNoPosts => 'لا توجد منشورات حتى الآن.';

  @override
  String adminErrorStories(Object error) {
    return 'حدث خطأ في جلب القصص: $error';
  }

  @override
  String get adminNoStories => 'لا توجد قصص حتى الآن.';

  @override
  String get bannedTitle => 'تم حظر الحساب';

  @override
  String get bannedMessage =>
      'موقوف مؤقتاً أو دائماً، الرجاء التواصل مع الدعم لاعادة تنشيط الحساب';

  @override
  String get bannedLogout => 'تسجيل الخروج';

  @override
  String get featureIdeasTitle => 'مختبر زامل';

  @override
  String get featureIdeasSubtitle => 'جرب الميزات الجديدة قبل الجميع';

  @override
  String get featureIdeasBeta => 'ميزات تجريبية (Beta)';

  @override
  String get featureIdeasFocusMode => 'وضع التركيز';

  @override
  String get featureIdeasFocusModeSubtitle =>
      'كتم جميع الإشعارات أثناء جلسات المذاكرة';

  @override
  String get featureIdeasCinemaMode => 'الوضع السينمائي لأطياف';

  @override
  String get featureIdeasCinemaModeSubtitle =>
      'تشغيل المقاطع بخلفية داكنة تماماً';

  @override
  String get featureIdeasRewards => 'مكافآت التفاعل';

  @override
  String get featureIdeasVerifyBadge => 'تفعيل علامة التوثيق';

  @override
  String get featureIdeasVerifyBadgeSubtitle =>
      'احصل على الشارة الزرقاء بجانب اسمك';

  @override
  String get featureIdeasActivateNow => 'تفعيل الآن';

  @override
  String get featureIdeasNeedPoints => '500 نقطة';

  @override
  String get featureIdeasVoteTitle => 'صوّت للميزات القادمة';

  @override
  String get featureIdeasNoIdeas => 'لا توجد ميزات مطروحة للتصويت حالياً.';

  @override
  String get featureIdeasVote => 'صوّت';

  @override
  String get featureIdeasVoted => 'تم التصويت';

  @override
  String get featureIdeasRequestSent => 'تم إرسال طلب التوثيق للإدارة بنجاح 🎉';

  @override
  String get featureIdeasNewFeature => 'ميزة جديدة';
}
