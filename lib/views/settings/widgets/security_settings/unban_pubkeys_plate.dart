import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/unban_pubkeys_dialog.dart';

/// Widget for unbanning public keys from the main security settings.
///
/// This widget provides a consistent layout similar to other security actions
/// and allows users to unban all banned public keys without requiring
/// password authentication. It integrates with the SecuritySettingsBloc
/// for state management and provides loading states and error handling.
class UnbanPubkeysPlate extends StatefulWidget {
  const UnbanPubkeysPlate({super.key, this.onUnbanComplete});

  /// Optional callback that is called when the unban operation completes.
  final VoidCallback? onUnbanComplete;

  @override
  State<UnbanPubkeysPlate> createState() => _UnbanPubkeysPlateState();
}

class _UnbanPubkeysPlateState extends State<UnbanPubkeysPlate> {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return BlocListener<SecuritySettingsBloc, SecuritySettingsState>(
      listener: _handleStateChanges,
      child: BlocBuilder<SecuritySettingsBloc, SecuritySettingsState>(
        builder: (context, state) {
          return SecurityActionPlate(
            icon: Icon(Icons.block),
            title: LocaleKeys.unbanPubkeys.tr(),
            description: LocaleKeys.unbanPubkeysDescription.tr(),
            trailingWidget: UiPrimaryButton(
              onPressed:
                  state.isUnbanningPubkeys ? null : () => _handleUnbanPressed(context),
              width: isMobile ? double.infinity : 210.0,
              height: isMobile ? 52.0 : 40.0,
              text: state.isUnbanningPubkeys
                  ? '${LocaleKeys.unbanPubkeys.tr()}...'
                  : LocaleKeys.unbanPubkeys.tr(),
              textStyle: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: palette.onBrand),
            ),
          );
        },
      ),
    );
  }

  /// Handles state changes from the SecuritySettingsBloc.
  void _handleStateChanges(BuildContext context, SecuritySettingsState state) {
    // Handle successful unban completion
    if (state.unbanResult != null && !state.isUnbanningPubkeys) {
      final result = state.unbanResult!;

      // Check if there are meaningful results to show in dialog
      final hasResults =
          result.unbanned.isNotEmpty ||
          result.stillBanned.isNotEmpty ||
          result.wereNotBanned.isNotEmpty;

      if (hasResults) {
        // Show dialog with detailed results
        _showResultDialog(context, result);
      } else {
        // Show snackbar for empty results
        _showSnackbar(context, result);
      }

      widget.onUnbanComplete?.call();
    }

    // Handle unban errors
    if (state.unbanError != null && !state.isUnbanningPubkeys) {
      _showErrorSnackbar(context, state.unbanError!);
    }
  }

  /// Handles the unban button press by triggering the bloc event.
  void _handleUnbanPressed(BuildContext context) {
    context.read<SecuritySettingsBloc>().add(const UnbanPubkeysEvent());
  }

  /// Shows the results dialog with unban operation details.
  Future<void> _showResultDialog(
    BuildContext context,
    UnbanPubkeysResult result,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => UnbanPubkeysResultDialog(result: result),
    );
  }

  /// Shows appropriate snackbar based on unban results.
  void _showSnackbar(BuildContext context, UnbanPubkeysResult result) {
    if (!mounted) return;
    final palette = AppPalette.of(context);

    if (result.unbanned.isNotEmpty) {
      // Show success snackbar if any pubkeys were unbanned
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              LocaleKeys.unbannedPubkeys.plural(result.unbanned.length),
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(color: palette.success),
            ),
          ),
          backgroundColor: palette.successBg,
          closeIconColor: palette.success,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      // Show info snackbar if no pubkeys were banned
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              LocaleKeys.noBannedPubkeys.tr(),
              softWrap: true,
              overflow: TextOverflow.visible,
              style: TextStyle(color: palette.info),
            ),
          ),
          backgroundColor: palette.infoBg,
          closeIconColor: palette.info,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Shows error snackbar when unban operation fails.
  void _showErrorSnackbar(BuildContext context, String error) {
    if (!mounted) return;
    final palette = AppPalette.of(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            LocaleKeys.unbanPubkeysFailed.tr(),
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(color: palette.danger),
          ),
        ),
        backgroundColor: palette.dangerBg,
        closeIconColor: palette.danger,
        duration: const Duration(seconds: 5),
      ),
    );

    // Log error for debugging
    debugPrint('Failed to unban pubkeys: $error');
  }
}
