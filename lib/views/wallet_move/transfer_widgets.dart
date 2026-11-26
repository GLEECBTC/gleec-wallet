import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show WalletId;
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';

/// A step's heading, announced as one.
class TransferTitle extends StatelessWidget {
  const TransferTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
    ),
  );
}

/// Body copy at full contrast: the theme's bodyLarge is half-transparent.
class TransferText extends StatelessWidget {
  const TransferText(this.text, {this.bold = false, super.key});

  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: bold ? FontWeight.w700 : null,
      ),
    );
  }
}

/// One numbered instruction. The number is drawn, not read: the reading
/// order already gives it.
class TransferStep extends StatelessWidget {
  const TransferStep({required this.number, required this.text, super.key});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Grows with the text, so the number never clips at large sizes.
    final badge = MediaQuery.textScalerOf(context).scale(28);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: badge,
              height: badge,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.16),
              ),
              child: Text(
                '$number',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: TransferText(text)),
        ],
      ),
    );
  }
}

/// Opens a Security settings flow over the whole app. It closes itself when
/// the wallet it was opened for signs out or is switched, so it never acts
/// for another wallet.
Future<void> openTransferFlow(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  final walletId = context.read<AuthBloc>().state.currentUser?.walletId;
  if (walletId == null) return Future.value();
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (context) =>
          TransferFlowPage(title: title, walletId: walletId, child: builder),
    ),
  );
}

class TransferFlowPage extends StatelessWidget {
  const TransferFlowPage({
    required this.title,
    required this.walletId,
    required this.child,
    super.key,
  });

  final String title;
  final WalletId walletId;
  final WidgetBuilder child;

  @override
  Widget build(BuildContext context) => BlocListener<AuthBloc, AuthBlocState>(
    listenWhen: (_, current) => current.currentUser?.walletId != walletId,
    listener: (context, _) {
      // Only this route: whatever is above it may already have closed.
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    },
    child: Scaffold(
      // Styled as the Security page's own mobile header, which opened it.
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
        foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Builder(builder: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Closes the flow page [context] is in, and only that page.
void closeTransferFlow(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  final navigator = Navigator.of(context);
  route.isCurrent ? navigator.pop() : navigator.removeRoute(route);
}

/// Opaque body text for list rows: the dialog's theme draws bodyLarge and
/// bodySmall half-transparent, as the setup entry screen notes.
class TransferOpaqueText extends StatelessWidget {
  const TransferOpaqueText({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          bodySmall: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Keeps keyboard focus inside a step that replaced the one holding it,
/// resting on no button, as the wallet access panels do. Key it by step.
///
/// [announce] is read out when the step appears, so a screen reader hears
/// that the screen changed under it. Leave it out for a flow's first step.
class TransferStepFocus extends StatefulWidget {
  const TransferStepFocus({required this.child, this.announce, super.key});

  final Widget child;
  final String? announce;

  @override
  State<TransferStepFocus> createState() => _TransferStepFocusState();
}

class _TransferStepFocusState extends State<TransferStepFocus> {
  @override
  void initState() {
    super.initState();
    final message = widget.announce;
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ).ignore();
    });
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, skipTraversal: true, child: widget.child);
}
