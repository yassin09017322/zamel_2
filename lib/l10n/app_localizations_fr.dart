// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

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
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsInterface => 'Interface';

  @override
  String get settingsDarkMode => 'Mode sombre';

  @override
  String get settingsDarkModeSubtitle =>
      'Une interface confortable de jour comme de nuit';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSubtitle => 'Choisissez votre langue préférée';

  @override
  String get settingsCustomMode => 'Mode personnalisé';

  @override
  String get settingsCustomModeSubtitle =>
      'Masquer les éléments inutiles et simplifier l\'écran';

  @override
  String get settingsNotifications => 'Notifications et actualisation';

  @override
  String get settingsSoundNotifications => 'Alertes sonores';

  @override
  String get settingsSoundNotificationsSubtitle =>
      'Alertes claires pour les messages et les appels';

  @override
  String get settingsAutoRefresh =>
      'Actualisation automatique des publications';

  @override
  String get settingsAutoRefreshSubtitle =>
      'Garder les nouvelles publications à jour';

  @override
  String get settingsPresence => 'Afficher l\'état de connexion';

  @override
  String get settingsPresenceSubtitle =>
      'Afficher le statut en ligne dans les conversations';

  @override
  String get settingsCompactMode => 'Mise en page compacte';

  @override
  String get settingsCompactModeSubtitle =>
      'Réduire les espaces et les éléments';

  @override
  String get settingsGlobalTitle => 'L\'application est mondiale';

  @override
  String get settingsGlobalSubtitle =>
      'Une expérience adaptée aux utilisateurs du monde entier.';

  @override
  String get settingsResetTitle => 'Réinitialiser les paramètres';

  @override
  String get settingsResetSubtitle => 'Restaurer les valeurs par défaut.';

  @override
  String get settingsResetSuccess => 'Paramètres réinitialisés';

  @override
  String get settingsAboutTitle => 'À propos de l\'application';

  @override
  String get settingsAboutSubtitle =>
      'ZAMEL avec prise en charge de Firebase et des fonctionnalités mondiales.';

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
