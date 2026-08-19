import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ZAMEL'**
  String get appTitle;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginSubtitle;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginButton;

  /// No description provided for @loginInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get loginInvalidEmail;

  /// No description provided for @loginInvalidPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid password (at least 6 characters)'**
  String get loginInvalidPassword;

  /// No description provided for @loginResetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get loginResetPasswordTitle;

  /// No description provided for @loginResetPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your registered email'**
  String get loginResetPasswordHint;

  /// No description provided for @loginResetPasswordCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get loginResetPasswordCancel;

  /// No description provided for @loginResetPasswordSend.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get loginResetPasswordSend;

  /// No description provided for @loginResetPasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'A password reset link has been sent to your email.'**
  String get loginResetPasswordSuccess;

  /// No description provided for @loginSignUpPrompt.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get loginSignUpPrompt;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// No description provided for @usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// No description provided for @createAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccountButton;

  /// No description provided for @registerInvalidUsername.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get registerInvalidUsername;

  /// No description provided for @registerInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get registerInvalidEmail;

  /// No description provided for @registerInvalidPassword.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get registerInvalidPassword;

  /// No description provided for @registerPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get registerPasswordMismatch;

  /// No description provided for @registerAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get registerAlreadyHaveAccount;

  /// No description provided for @registerSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Account confirmed'**
  String get registerSuccessTitle;

  /// No description provided for @registerSuccessContent.
  ///
  /// In en, this message translates to:
  /// **'Your account has been created successfully. Please check your email to activate it.'**
  String get registerSuccessContent;

  /// No description provided for @registerSuccessButton.
  ///
  /// In en, this message translates to:
  /// **'Okay, got it'**
  String get registerSuccessButton;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsInterface.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get settingsInterface;

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get settingsDarkMode;

  /// No description provided for @settingsDarkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A comfortable look for day or night'**
  String get settingsDarkModeSubtitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your preferred language'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsCustomMode.
  ///
  /// In en, this message translates to:
  /// **'Custom mode'**
  String get settingsCustomMode;

  /// No description provided for @settingsCustomModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide unnecessary elements and simplify the screen'**
  String get settingsCustomModeSubtitle;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications & refresh'**
  String get settingsNotifications;

  /// No description provided for @settingsSoundNotifications.
  ///
  /// In en, this message translates to:
  /// **'Sound alerts'**
  String get settingsSoundNotifications;

  /// No description provided for @settingsSoundNotificationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear alerts for messages and calls'**
  String get settingsSoundNotificationsSubtitle;

  /// No description provided for @settingsAutoRefresh.
  ///
  /// In en, this message translates to:
  /// **'Auto refresh posts'**
  String get settingsAutoRefresh;

  /// No description provided for @settingsAutoRefreshSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep new posts updated automatically'**
  String get settingsAutoRefreshSubtitle;

  /// No description provided for @settingsPresence.
  ///
  /// In en, this message translates to:
  /// **'Show connection status'**
  String get settingsPresence;

  /// No description provided for @settingsPresenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display online status in chats and conversations'**
  String get settingsPresenceSubtitle;

  /// No description provided for @settingsCompactMode.
  ///
  /// In en, this message translates to:
  /// **'Compact layout'**
  String get settingsCompactMode;

  /// No description provided for @settingsCompactModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reduce spacing and elements for smoother browsing'**
  String get settingsCompactModeSubtitle;

  /// No description provided for @settingsGlobalTitle.
  ///
  /// In en, this message translates to:
  /// **'The app is global'**
  String get settingsGlobalTitle;

  /// No description provided for @settingsGlobalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Supports multiple languages and provides a suitable experience for users around the world.'**
  String get settingsGlobalSubtitle;

  /// No description provided for @settingsResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get settingsResetTitle;

  /// No description provided for @settingsResetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore default values for all options.'**
  String get settingsResetSubtitle;

  /// No description provided for @settingsResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settings were reset successfully'**
  String get settingsResetSuccess;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About the app'**
  String get settingsAboutTitle;

  /// No description provided for @settingsAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'ZAMEL is a customized version of the previous app with Firebase support and global features.'**
  String get settingsAboutSubtitle;

  /// No description provided for @adminTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin panel'**
  String get adminTitle;

  /// No description provided for @adminLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to access the admin panel.'**
  String get adminLoginRequired;

  /// No description provided for @adminRoleRequired.
  ///
  /// In en, this message translates to:
  /// **'Sorry, this page is only available to administrators.'**
  String get adminRoleRequired;

  /// No description provided for @adminUsersTab.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUsersTab;

  /// No description provided for @adminPostsTab.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get adminPostsTab;

  /// No description provided for @adminStoriesTab.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get adminStoriesTab;

  /// No description provided for @adminErrorUsers.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading users: {error}'**
  String adminErrorUsers(Object error);

  /// No description provided for @adminNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No users yet.'**
  String get adminNoUsers;

  /// No description provided for @adminFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers {count}'**
  String adminFollowers(Object count);

  /// No description provided for @adminPoints.
  ///
  /// In en, this message translates to:
  /// **'Points {points}'**
  String adminPoints(Object points);

  /// No description provided for @adminBlockedFromPosting.
  ///
  /// In en, this message translates to:
  /// **'Blocked from posting'**
  String get adminBlockedFromPosting;

  /// No description provided for @adminBanned.
  ///
  /// In en, this message translates to:
  /// **'Banned'**
  String get adminBanned;

  /// No description provided for @adminUnbanUser.
  ///
  /// In en, this message translates to:
  /// **'Unban'**
  String get adminUnbanUser;

  /// No description provided for @adminBanUser.
  ///
  /// In en, this message translates to:
  /// **'Ban user'**
  String get adminBanUser;

  /// No description provided for @adminDisablePosting.
  ///
  /// In en, this message translates to:
  /// **'Disable posting'**
  String get adminDisablePosting;

  /// No description provided for @adminEnablePosting.
  ///
  /// In en, this message translates to:
  /// **'Enable posting'**
  String get adminEnablePosting;

  /// No description provided for @adminUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get adminUpgrade;

  /// No description provided for @adminDowngrade.
  ///
  /// In en, this message translates to:
  /// **'Downgrade'**
  String get adminDowngrade;

  /// No description provided for @adminUserBanSuccess.
  ///
  /// In en, this message translates to:
  /// **'User banned'**
  String get adminUserBanSuccess;

  /// No description provided for @adminUserUnbanSuccess.
  ///
  /// In en, this message translates to:
  /// **'User unbanned'**
  String get adminUserUnbanSuccess;

  /// No description provided for @adminPostingEnabled.
  ///
  /// In en, this message translates to:
  /// **'Posting enabled for the user'**
  String get adminPostingEnabled;

  /// No description provided for @adminPostingDisabled.
  ///
  /// In en, this message translates to:
  /// **'Posting disabled for the user'**
  String get adminPostingDisabled;

  /// No description provided for @adminPromoted.
  ///
  /// In en, this message translates to:
  /// **'User promoted to admin'**
  String get adminPromoted;

  /// No description provided for @adminDemoted.
  ///
  /// In en, this message translates to:
  /// **'User demoted to regular user'**
  String get adminDemoted;

  /// No description provided for @adminErrorPosts.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading posts: {error}'**
  String adminErrorPosts(Object error);

  /// No description provided for @adminNoPosts.
  ///
  /// In en, this message translates to:
  /// **'No posts yet.'**
  String get adminNoPosts;

  /// No description provided for @adminErrorStories.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading stories: {error}'**
  String adminErrorStories(Object error);

  /// No description provided for @adminNoStories.
  ///
  /// In en, this message translates to:
  /// **'No stories yet.'**
  String get adminNoStories;

  /// No description provided for @bannedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account blocked'**
  String get bannedTitle;

  /// No description provided for @bannedMessage.
  ///
  /// In en, this message translates to:
  /// **'Temporarily or permanently suspended. Please contact support to reactivate your account.'**
  String get bannedMessage;

  /// No description provided for @bannedLogout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get bannedLogout;

  /// No description provided for @featureIdeasTitle.
  ///
  /// In en, this message translates to:
  /// **'ZAMEL Lab'**
  String get featureIdeasTitle;

  /// No description provided for @featureIdeasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try the new features before everyone else'**
  String get featureIdeasSubtitle;

  /// No description provided for @featureIdeasBeta.
  ///
  /// In en, this message translates to:
  /// **'Experimental features (Beta)'**
  String get featureIdeasBeta;

  /// No description provided for @featureIdeasFocusMode.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get featureIdeasFocusMode;

  /// No description provided for @featureIdeasFocusModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mute all notifications during study sessions'**
  String get featureIdeasFocusModeSubtitle;

  /// No description provided for @featureIdeasCinemaMode.
  ///
  /// In en, this message translates to:
  /// **'Cinema mode for Atyaaf'**
  String get featureIdeasCinemaMode;

  /// No description provided for @featureIdeasCinemaModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play clips with a fully dark background'**
  String get featureIdeasCinemaModeSubtitle;

  /// No description provided for @featureIdeasRewards.
  ///
  /// In en, this message translates to:
  /// **'Interaction rewards'**
  String get featureIdeasRewards;

  /// No description provided for @featureIdeasVerifyBadge.
  ///
  /// In en, this message translates to:
  /// **'Activate verification badge'**
  String get featureIdeasVerifyBadge;

  /// No description provided for @featureIdeasVerifyBadgeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get the blue badge next to your name'**
  String get featureIdeasVerifyBadgeSubtitle;

  /// No description provided for @featureIdeasActivateNow.
  ///
  /// In en, this message translates to:
  /// **'Activate now'**
  String get featureIdeasActivateNow;

  /// No description provided for @featureIdeasNeedPoints.
  ///
  /// In en, this message translates to:
  /// **'500 points'**
  String get featureIdeasNeedPoints;

  /// No description provided for @featureIdeasVoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Vote for upcoming features'**
  String get featureIdeasVoteTitle;

  /// No description provided for @featureIdeasNoIdeas.
  ///
  /// In en, this message translates to:
  /// **'No features are currently available for voting.'**
  String get featureIdeasNoIdeas;

  /// No description provided for @featureIdeasVote.
  ///
  /// In en, this message translates to:
  /// **'Vote'**
  String get featureIdeasVote;

  /// No description provided for @featureIdeasVoted.
  ///
  /// In en, this message translates to:
  /// **'Voted'**
  String get featureIdeasVoted;

  /// No description provided for @featureIdeasRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Verification request sent to the administration successfully 🎉'**
  String get featureIdeasRequestSent;

  /// No description provided for @featureIdeasNewFeature.
  ///
  /// In en, this message translates to:
  /// **'New feature'**
  String get featureIdeasNewFeature;
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
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
