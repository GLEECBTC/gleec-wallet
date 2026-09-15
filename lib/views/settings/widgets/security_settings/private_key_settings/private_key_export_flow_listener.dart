import 'package:web_dex/generated/codegen_loader.g.dart';
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_labels.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_password_dialog.dart';
import 'package:web_dex/views/wallet/coin_details/receive/qr_code_address.dart';

/// Owns only routes and presentation effects; export work stays in the BLoC.
class PrivateKeyExportFlowListener extends StatefulWidget {
  const PrivateKeyExportFlowListener({required this.child, super.key});

  final Widget child;

  @override
  State<PrivateKeyExportFlowListener> createState() =>
      _PrivateKeyExportFlowListenerState();
}

class _PrivateKeyExportFlowListenerState
    extends State<PrivateKeyExportFlowListener> {
  DialogRoute<void>? _passwordRoute;
  DialogRoute<void>? _qrRoute;
  int _lastDeliveryRevision = 0;
  int _lastOperation = 0;

  static void _remove(DialogRoute<void>? route) {
    if (route?.isActive ?? false) route!.navigator?.removeRoute(route);
  }

  void _listen(BuildContext context, PrivateKeyExportState state) {
    if (_lastOperation != state.operationId) {
      _lastOperation = state.operationId;
      _lastDeliveryRevision = 0;
    }
    if (state.needsPasswordDialog) {
      if (_passwordRoute == null) _openPassword(context, state.operationId);
    } else {
      final route = _passwordRoute;
      _passwordRoute = null;
      _remove(route);
    }
    if (state.qrKey != null &&
        state.showKeys &&
        state.phase == PrivateKeyExportPhase.ready) {
      if (_qrRoute == null) _openQr(context, state.operationId);
    } else {
      final route = _qrRoute;
      _qrRoute = null;
      _remove(route);
    }

    final navigation = context.read<SecuritySettingsBloc>();
    if (state.phase == PrivateKeyExportPhase.ready &&
        navigation.state.step != SecuritySettingsStep.privateKeyShow) {
      navigation.add(const ShowPrivateKeysEvent());
    } else if ((state.phase == PrivateKeyExportPhase.idle ||
            state.phase == PrivateKeyExportPhase.failed) &&
        navigation.state.step == SecuritySettingsStep.privateKeyShow) {
      navigation.add(const ResetEvent());
    }
    if (state.phase == PrivateKeyExportPhase.failed && state.error != null) {
      _showMessage(context, privateKeyExportErrorText(state.error!));
    }
    if (state.deliveryRevision != _lastDeliveryRevision) {
      _lastDeliveryRevision = state.deliveryRevision;
      if (state.deliveryFailed) {
        _showMessage(context, LocaleKeys.privateKeyExportDeliveryFailed.tr());
      } else if (state.deliveryOutcome ==
          PrivateKeyExportDeliveryOutcome.unconfirmed) {
        _showMessage(
          context,
          LocaleKeys.privateKeyExportDeliveryUnconfirmed.tr(),
        );
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openPassword(BuildContext context, int operation) {
    final bloc = context.read<PrivateKeyExportBloc>();
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<PrivateKeyExportBloc, PrivateKeyExportState>(
          builder: (context, state) {
            if (!state.needsPasswordDialog || state.operationId != operation) {
              return const SizedBox.shrink();
            }
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) bloc.add(const PrivateKeyExportCancelled());
              },
              child: Dialog(
                child: PrivateKeyExportPasswordDialog(
                  walletName: state.walletName,
                  isLoading: state.phase == PrivateKeyExportPhase.exporting,
                  errorText: state.error == null
                      ? null
                      : privateKeyExportErrorText(state.error!),
                  onSubmit: (password) => bloc.add(
                    PrivateKeyExportPasswordSubmitted(operation, password),
                  ),
                  onCancel: () => bloc.add(const PrivateKeyExportCancelled()),
                ),
              ),
            );
          },
        ),
      ),
    );
    _passwordRoute = route;
    unawaited(
      Navigator.of(context).push(route).whenComplete(() {
        if (identical(_passwordRoute, route)) _passwordRoute = null;
        if (!bloc.isClosed &&
            bloc.state.operationId == operation &&
            bloc.state.needsPasswordDialog) {
          bloc.add(const PrivateKeyExportCancelled());
        }
      }),
    );
  }

  void _openQr(BuildContext context, int operation) {
    final bloc = context.read<PrivateKeyExportBloc>();
    final route = DialogRoute<void>(
      context: context,
      builder: (_) =>
          BlocProvider.value(value: bloc, child: const _PrivateKeyQrDialog()),
    );
    _qrRoute = route;
    unawaited(
      Navigator.of(context).push(route).whenComplete(() {
        if (identical(_qrRoute, route)) _qrRoute = null;
        if (!bloc.isClosed && bloc.state.operationId == operation) {
          bloc.add(const PrivateKeyExportQrClosed());
        }
      }),
    );
  }

  @override
  void dispose() {
    final password = _passwordRoute;
    final qr = _qrRoute;
    // Route removal during a parent route's disposal can lock the navigator.
    // The dialogs read cleared BLoC state immediately; remove their own routes
    // after the parent finishes its navigation update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _remove(password);
      _remove(qr);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<PrivateKeyExportBloc, PrivateKeyExportState>(
        listener: _listen,
        child: widget.child,
      );
}

class _PrivateKeyQrDialog extends StatelessWidget {
  const _PrivateKeyQrDialog();

  @override
  Widget build(BuildContext context) => ScreenshotSensitive(
    child: BlocBuilder<PrivateKeyExportBloc, PrivateKeyExportState>(
      builder: (context, state) {
        final reference = state.qrKey;
        final key = reference == null
            ? null
            : state.keyAt(reference.$1, reference.$2);
        if (key == null ||
            !state.showKeys ||
            state.phase != PrivateKeyExportPhase.ready) {
          return const SizedBox.shrink();
        }
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(key.assetId.id)),
                      IconButton(
                        onPressed: () => context
                            .read<PrivateKeyExportBloc>()
                            .add(const PrivateKeyExportQrClosed()),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (key.hdInfo?.derivationPath case final String path)
                    SelectableText(path),
                  QRCodeAddress(currentAddress: key.privateKey),
                  SelectableText(key.privateKey),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
