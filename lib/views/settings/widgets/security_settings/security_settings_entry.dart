import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/router/state/routing_state.dart';

/// A task the Security page starts as soon as it is on screen, so a reminder
/// elsewhere in the app leads to the task it names instead of to a list.
enum SecuritySettingsEntry { recoveryPhrase, walletPassword }

/// The task waiting for the Security page. The page takes it when it opens.
final ValueNotifier<SecuritySettingsEntry?> pendingSecuritySettingsEntry =
    ValueNotifier<SecuritySettingsEntry?>(null);

/// Whether the recovery phrase is being shown or confirmed in Security
/// settings. Reminders to back it up stay out of the way meanwhile.
final ValueNotifier<bool> recoveryPhraseFlowOnScreen = ValueNotifier<bool>(
  false,
);

/// Opens Security settings, at [entry] when one is given.
void openSecuritySettings({SecuritySettingsEntry? entry}) {
  pendingSecuritySettingsEntry.value = entry;
  routingState.settingsState.openSecurity();
  if (entry != null) _expireUnlessTaken(entry, frames: 3);
}

/// Drops a request the page did not pick up, so opening Security later by
/// hand never starts a task nobody is asking for any more.
void _expireUnlessTaken(SecuritySettingsEntry entry, {required int frames}) {
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) {
    if (pendingSecuritySettingsEntry.value != entry) return;
    if (frames <= 1) {
      pendingSecuritySettingsEntry.value = null;
    } else {
      _expireUnlessTaken(entry, frames: frames - 1);
    }
  });
  binding.ensureVisualUpdate();
}

/// Starts the task the Security page was opened for, once the page is built
/// and whenever a new one is requested while it is showing.
class SecuritySettingsEntryRunner extends StatefulWidget {
  const SecuritySettingsEntryRunner({
    required this.onRecoveryPhrase,
    required this.child,
    super.key,
  });

  /// Authorizes and opens the recovery phrase, as the page's own action does.
  final void Function(BuildContext context) onRecoveryPhrase;
  final Widget child;

  @override
  State<SecuritySettingsEntryRunner> createState() =>
      _SecuritySettingsEntryRunnerState();
}

class _SecuritySettingsEntryRunnerState
    extends State<SecuritySettingsEntryRunner> {
  @override
  void initState() {
    super.initState();
    pendingSecuritySettingsEntry.addListener(_take);
    // Dialogs and navigation wait for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _take());
  }

  @override
  void dispose() {
    pendingSecuritySettingsEntry.removeListener(_take);
    super.dispose();
  }

  void _take() {
    if (!mounted) return;
    final entry = pendingSecuritySettingsEntry.value;
    if (entry == null) return;
    pendingSecuritySettingsEntry.value = null;
    switch (entry) {
      case SecuritySettingsEntry.recoveryPhrase:
        widget.onRecoveryPhrase(context);
      case SecuritySettingsEntry.walletPassword:
        context.read<SecuritySettingsBloc>().add(const PasswordUpdateEvent());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
