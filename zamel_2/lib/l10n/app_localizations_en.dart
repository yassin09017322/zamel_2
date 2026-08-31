// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ZAMEL';

  @override
  String get loginTitle => 'Sign in to your account';

  @override
  String get loginSubtitle => 'Welcome back';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get loginButton => 'Sign in';

  @override
  String get loginInvalidEmail => 'Please enter a valid email address';

  @override
  String get loginInvalidPassword =>
      'Please enter a valid password (at least 6 characters)';

  @override
  String get loginResetPasswordTitle => 'Reset password';

  @override
  String get loginResetPasswordHint => 'Enter your registered email';

  @override
  String get loginResetPasswordCancel => 'Cancel';

  @override
  String get loginResetPasswordSend => 'Send link';

  @override
  String get loginResetPasswordSuccess =>
      'A password reset link has been sent to your email.';

  @override
  String get loginSignUpPrompt => 'Don\'t have an account? Sign up';

  @override
  String get registerTitle => 'Create account';

  @override
  String get usernameLabel => 'Username';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get createAccountButton => 'Create account';

  @override
  String get registerInvalidUsername =>
      'Username must be at least 3 characters';

  @override
  String get registerInvalidEmail => 'Please enter a valid email address';

  @override
  String get registerInvalidPassword =>
      'Password must be at least 6 characters';

  @override
  String get registerPasswordMismatch => 'Passwords do not match';

  @override
  String get registerAlreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get registerSuccessTitle => 'Account confirmed';

  @override
  String get registerSuccessContent =>
      'Your account has been created successfully. Please check your email to activate it.';

  @override
  String get registerSuccessButton => 'Okay, got it';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsInterface => 'Interface';

  @override
  String get settingsDarkMode => 'Dark mode';

  @override
  String get settingsDarkModeSubtitle => 'A comfortable look for day or night';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle => 'Choose your preferred language';

  @override
  String get settingsCustomMode => 'Custom mode';

  @override
  String get settingsCustomModeSubtitle =>
      'Hide unnecessary elements and simplify the screen';

  @override
  String get settingsNotifications => 'Notifications & refresh';

  @override
  String get settingsSoundNotifications => 'Sound alerts';

  @override
  String get settingsSoundNotificationsSubtitle =>
      'Clear alerts for messages and calls';

  @override
  String get settingsAutoRefresh => 'Auto refresh posts';

  @override
  String get settingsAutoRefreshSubtitle =>
      'Keep new posts updated automatically';

  @override
  String get settingsPresence => 'Show connection status';

  @override
  String get settingsPresenceSubtitle =>
      'Display online status in chats and conversations';

  @override
  String get settingsCompactMode => 'Compact layout';

  @override
  String get settingsCompactModeSubtitle =>
      'Reduce spacing and elements for smoother browsing';

  @override
  String get settingsGlobalTitle => 'The app is global';

  @override
  String get settingsGlobalSubtitle =>
      'Supports multiple languages and provides a suitable experience for users around the world.';

  @override
  String get settingsResetTitle => 'Reset settings';

  @override
  String get settingsResetSubtitle => 'Restore default values for all options.';

  @override
  String get settingsResetSuccess => 'Settings were reset successfully';

  @override
  String get settingsAboutTitle => 'About the app';

  @override
  String get settingsAboutSubtitle =>
      'ZAMEL is a customized version of the previous app with Firebase support and global features.';

  @override
  String get adminTitle => 'Admin panel';

  @override
  String get adminLoginRequired => 'Please sign in to access the admin panel.';

  @override
  String get adminRoleRequired =>
      'Sorry, this page is only available to administrators.';

  @override
  String get adminUsersTab => 'Users';

  @override
  String get adminPostsTab => 'Posts';

  @override
  String get adminStoriesTab => 'Stories';

  @override
  String adminErrorUsers(Object error) {
    return 'An error occurred while loading users: $error';
  }

  @override
  String get adminNoUsers => 'No users yet.';

  @override
  String adminFollowers(Object count) {
    return 'Followers $count';
  }

  @override
  String adminPoints(Object points) {
    return 'Points $points';
  }

  @override
  String get adminBlockedFromPosting => 'Blocked from posting';

  @override
  String get adminBanned => 'Banned';

  @override
  String get adminUnbanUser => 'Unban';

  @override
  String get adminBanUser => 'Ban user';

  @override
  String get adminDisablePosting => 'Disable posting';

  @override
  String get adminEnablePosting => 'Enable posting';

  @override
  String get adminUpgrade => 'Upgrade';

  @override
  String get adminDowngrade => 'Downgrade';

  @override
  String get adminUserBanSuccess => 'User banned';

  @override
  String get adminUserUnbanSuccess => 'User unbanned';

  @override
  String get adminPostingEnabled => 'Posting enabled for the user';

  @override
  String get adminPostingDisabled => 'Posting disabled for the user';

  @override
  String get adminPromoted => 'User promoted to admin';

  @override
  String get adminDemoted => 'User demoted to regular user';

  @override
  String adminErrorPosts(Object error) {
    return 'An error occurred while loading posts: $error';
  }

  @override
  String get adminNoPosts => 'No posts yet.';

  @override
  String adminErrorStories(Object error) {
    return 'An error occurred while loading stories: $error';
  }

  @override
  String get adminNoStories => 'No stories yet.';

  @override
  String get bannedTitle => 'Account blocked';

  @override
  String get bannedMessage =>
      'Temporarily or permanently suspended. Please contact support to reactivate your account.';

  @override
  String get bannedLogout => 'Sign out';

  @override
  String get featureIdeasTitle => 'ZAMEL Lab';

  @override
  String get featureIdeasSubtitle =>
      'Try the new features before everyone else';

  @override
  String get featureIdeasBeta => 'Experimental features (Beta)';

  @override
  String get featureIdeasFocusMode => 'Focus mode';

  @override
  String get featureIdeasFocusModeSubtitle =>
      'Mute all notifications during study sessions';

  @override
  String get featureIdeasCinemaMode => 'Cinema mode for Atyaaf';

  @override
  String get featureIdeasCinemaModeSubtitle =>
      'Play clips with a fully dark background';

  @override
  String get featureIdeasRewards => 'Interaction rewards';

  @override
  String get featureIdeasVerifyBadge => 'Activate verification badge';

  @override
  String get featureIdeasVerifyBadgeSubtitle =>
      'Get the blue badge next to your name';

  @override
  String get featureIdeasActivateNow => 'Activate now';

  @override
  String get featureIdeasNeedPoints => '500 points';

  @override
  String get featureIdeasVoteTitle => 'Vote for upcoming features';

  @override
  String get featureIdeasNoIdeas =>
      'No features are currently available for voting.';

  @override
  String get featureIdeasVote => 'Vote';

  @override
  String get featureIdeasVoted => 'Voted';

  @override
  String get featureIdeasRequestSent =>
      'Verification request sent to the administration successfully 🎉';

  @override
  String get featureIdeasNewFeature => 'New feature';
}
