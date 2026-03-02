import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/3p_api/faucet/faucet_response.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/widgets/faucet_message.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_bloc.dart';

class FaucetView extends StatelessWidget {
  const FaucetView({
    Key? key,
    required this.coinAbbr,
    required this.coinAddress,
    required this.onClose,
  }) : super(key: key);

  final String coinAbbr;
  final String coinAddress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(16),
        child: BlocBuilder<FaucetBloc, FaucetState>(
          buildWhen: (previous, current) => previous != current,
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(title: title(state), onClose: onClose),
                _StatesOfPage(state: state, onClose: onClose),
              ],
            );
          },
        ),
      ),
    );
  }

  String title(FaucetState state) {
    if (state is FaucetRequestSuccess) {
      return state.response.status.title;
    } else if (state is FaucetRequestError) {
      return LocaleKeys.faucetFailureTitle.tr();
    } else if (state is FaucetRequestInProgress) {
      return LocaleKeys.faucetLoadingTitle.tr();
    } else if (state is FaucetInitial) {
      return LocaleKeys.faucetInitialTitle.tr();
    }
    return LocaleKeys.faucetFailureTitle.tr();
  }
}

class _DialogHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _DialogHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Positioned(
            right: -8,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatesOfPage extends StatelessWidget {
  final FaucetState state;
  final VoidCallback onClose;
  const _StatesOfPage({required this.state, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final localState = state;
    if (localState is FaucetRequestInProgress || localState is FaucetInitial) {
      return const _Loading();
    } else if (localState is FaucetRequestSuccess) {
      final bool isDenied = localState.response.status == FaucetStatus.denied;
      return _FaucetResult(
        color: isDenied
            ? theme.custom.decreaseColor
            : theme.custom.headerFloatBoxColor,
        icon: isDenied ? Icons.close_rounded : Icons.check_rounded,
        message: localState.response.message,
        onClose: onClose,
      );
    } else if (localState is FaucetRequestError) {
      return _FaucetResult(
        color: theme.custom.decreaseColor,
        icon: Icons.close_rounded,
        message: localState.message,
        onClose: onClose,
      );
    }

    return const SizedBox();
  }
}

class _Loading extends StatefulWidget {
  const _Loading();

  @override
  State<_Loading> createState() => _LoadingState();
}

class _LoadingState extends State<_Loading> {
  static const _dotInterval = Duration(milliseconds: 450);
  Timer? _timer;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_dotInterval, (_) {
      if (!mounted) return;
      setState(() {
        _dotCount = (_dotCount + 1) % 4;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        const Center(child: UiSpinner()),
        const SizedBox(height: 16),
        Text(
          '${LocaleKeys.faucetLoadingMessage.tr()}$dots',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          LocaleKeys.faucetLoadingSubtitle.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FaucetResult extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;
  final VoidCallback onClose;

  const _FaucetResult({
    Key? key,
    required this.color,
    required this.icon,
    required this.message,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 15.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: color, width: 4),
            ),
            child: Icon(icon, size: 66, color: color),
          ),
        ),
        const SizedBox(height: 12),
        FaucetMessage(message),
        const SizedBox(height: 20),
        Center(
          child: UiPrimaryButton(
            text: LocaleKeys.close.tr(),
            width: 324,
            onPressed: onClose,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
