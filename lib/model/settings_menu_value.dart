import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

enum SettingsMenuValue {
  general,
  security,
  privacy,
  kycPolicy,
  support,
  feedback,
  none;

  String get title {
    switch (this) {
      case SettingsMenuValue.general:
        return LocaleKeys.settingsMenuGeneral.tr();
      case SettingsMenuValue.security:
        return LocaleKeys.settingsMenuSecurity.tr();
      case SettingsMenuValue.privacy:
        return LocaleKeys.settingsMenuPrivacy.tr();
      case SettingsMenuValue.kycPolicy:
        return LocaleKeys.settingsMenuKycPolicy.tr();
      case SettingsMenuValue.support:
        return LocaleKeys.support.tr();
      case SettingsMenuValue.feedback:
        return LocaleKeys.feedback.tr();
      case SettingsMenuValue.none:
        return '';
    }
  }

  String get name {
    switch (this) {
      case SettingsMenuValue.general:
        return 'general';
      case SettingsMenuValue.security:
        return 'security';
      case SettingsMenuValue.privacy:
        return 'privacy';
      case SettingsMenuValue.kycPolicy:
        return 'kyc';
      case SettingsMenuValue.support:
        return 'support';
      case SettingsMenuValue.feedback:
        return 'feedback';
      case SettingsMenuValue.none:
        return 'none';
    }
  }
}
