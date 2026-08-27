import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/security_events.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_back_button.dart';
import 'package:web_dex/views/wallet/wallet_page/common/expandable_private_key_list.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_actions_widget.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// Widget for displaying private keys in a secure manner.
///
/// **Security Architecture**: This widget implements the UI layer of the hybrid
/// security approach for private key handling:
/// - Receives private key data directly from parent widget (not from BLoC state)
/// - Visibility state is managed by [SecuritySettingsBloc] for consistency
/// - Private key data never passes through shared state
/// - Provides secure viewing, copying, and QR code functionality
/// - Includes comprehensive security warnings and disclaimers
///
/// **Security Features**:
/// - Private keys are hidden by default
/// - Toggle visibility controlled by BLoC state
/// - Individual and bulk copy functionality
/// - QR code display for easy import
/// - Comprehensive security warnings and user education
/// - Proper cleanup when widget is disposed
class PrivateKeyShow extends StatelessWidget {
  /// Creates a new PrivateKeyShow widget.
  ///
  /// [privateKeys] Map of asset IDs to their corresponding private keys.
  /// **Security Note**: This data should be handled with extreme care and
  /// cleared from memory as soon as possible.
  const PrivateKeyShow({
    required this.privateKeys,
    this.blockedAssetIds = const <AssetId>{},
  });

  /// Private keys organized by asset ID.
  ///
  /// **Security Note**: This data is intentionally passed directly to the UI
  /// rather than stored in BLoC state to minimize memory exposure and lifetime.
  final Map<AssetId, List<PrivateKey>> privateKeys;
  final Set<AssetId> blockedAssetIds;

  @override
  Widget build(BuildContext context) {
    return ScreenshotSensitive(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: SeedBackButton(() {
                // Track analytics based on whether keys were copied
                final securityState = context
                    .read<SecuritySettingsBloc>()
                    .state;
                final wasBackupCompleted = securityState.arePrivateKeysSaved;

                final walletType =
                    context
                        .read<AuthBloc>()
                        .state
                        .currentUser
                        ?.wallet
                        .config
                        .type
                        .name ??
                    '';

                if (wasBackupCompleted) {
                  // User copied keys, so track as completed backup
                  context.read<AnalyticsBloc>().add(
                    AnalyticsBackupCompletedEvent(
                      backupTime: securityState.backupElapsed?.inSeconds ?? 0,
                      method: 'private_key_export',
                      hdType: walletType,
                    ),
                  );
                } else {
                  // User didn't copy keys, so track as skipped
                  context.read<AnalyticsBloc>().add(
                    AnalyticsBackupSkippedEvent(
                      stageSkipped: 'private_key_show',
                      hdType: walletType,
                    ),
                  );
                }

                context.read<SecuritySettingsBloc>().add(const ResetEvent());
              }),
            ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitleRow(),
              const SizedBox(height: 16),
              const _SecurityWarning(),
              const SizedBox(height: 16),
              const _CopyWarning(),
              const SizedBox(height: 16),
              PrivateKeyExportSection(
                privateKeys: privateKeys,
                blockedAssetIds: blockedAssetIds,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PrivateKeyExportSection extends StatefulWidget {
  const PrivateKeyExportSection({
    super.key,
    required this.privateKeys,
    required this.blockedAssetIds,
  });

  final Map<AssetId, List<PrivateKey>> privateKeys;
  final Set<AssetId> blockedAssetIds;

  @override
  State<PrivateKeyExportSection> createState() =>
      _PrivateKeyExportSectionState();
}

class _PrivateKeyExportSectionState extends State<PrivateKeyExportSection> {
  bool _includeBlockedAssets = false;

  @override
  void initState() {
    super.initState();
    _includeBlockedAssets = !_hasBlockedAssetsInKeys();
  }

  bool _hasBlockedAssetsInKeys() {
    if (widget.blockedAssetIds.isEmpty || widget.privateKeys.isEmpty) {
      return false;
    }
    for (final assetId in widget.privateKeys.keys) {
      if (widget.blockedAssetIds.contains(assetId)) return true;
    }
    return false;
  }

  Map<AssetId, List<PrivateKey>> _filteredPrivateKeys() {
    if (_includeBlockedAssets || widget.blockedAssetIds.isEmpty) {
      return widget.privateKeys;
    }
    final entries = widget.privateKeys.entries.where(
      (e) => !widget.blockedAssetIds.contains(e.key),
    );
    return Map<AssetId, List<PrivateKey>>.fromEntries(entries);
  }

  @override
  Widget build(BuildContext context) {
    final hasBlocked = _hasBlockedAssetsInKeys();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _ShowingSwitcher(),
            if (hasBlocked)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: _IncludeBlockedToggle(
                  value: _includeBlockedAssets,
                  onChanged: (val) =>
                      setState(() => _includeBlockedAssets = val),
                ),
              ),
            Flexible(
              child: PrivateKeyActionsWidget(
                privateKeys: _filteredPrivateKeys(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExpandablePrivateKeyList(privateKeys: _filteredPrivateKeys()),
      ],
    );
  }
}

class _IncludeBlockedToggle extends StatelessWidget {
  const _IncludeBlockedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiSwitcher(value: value, onChanged: onChanged, width: 38, height: 21),
          const SizedBox(width: 8),
          Text(
            LocaleKeys.includeBlockedAssets.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Widget displaying the title for private key export.
class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return Text(
      LocaleKeys.privateKeyExportTitle.tr(),
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}

/// Widget displaying a warning about copying private keys.
class _CopyWarning extends StatelessWidget {
  const _CopyWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.custom.warningColor.withValues(alpha: 0.1),
        border: Border.all(color: theme.custom.warningColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: theme.custom.warningColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              LocaleKeys.copyWarning.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: theme.custom.warningColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget displaying critical security warnings about private keys.
class _SecurityWarning extends StatelessWidget {
  const _SecurityWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                LocaleKeys.importantSecurityNotice.tr(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            LocaleKeys.privateKeySecurityWarning.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.red.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle switch for showing/hiding private keys.
class _ShowingSwitcher extends StatelessWidget {
  const _ShowingSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SecuritySettingsBloc, SecuritySettingsState, bool>(
      selector: (state) => state.showPrivateKeys,
      builder: (context, showPrivateKeys) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiSwitcher(
                value: showPrivateKeys,
                onChanged: (isChecked) => context
                    .read<SecuritySettingsBloc>()
                    .add(ShowPrivateKeysWordsEvent(isChecked)),
                width: 38,
                height: 21,
              ),
              const SizedBox(width: 8),
              Text(
                LocaleKeys.showPrivateKeys.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      },
    );
  }
}
