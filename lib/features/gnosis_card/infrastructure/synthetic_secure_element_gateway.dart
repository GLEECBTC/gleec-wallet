import 'package:flutter/material.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// Synthetic isolated surface. A future PSE iframe/native view replaces only
/// this adapter; PAN/CVC/PIN values never enter card domain state.
class SyntheticSecureElementGateway implements CardSecureElementGateway {
  const SyntheticSecureElementGateway();

  @override
  Future<void> showCardDetails(
    BuildContext context, {
    required String cardId,
  }) => _show(
    context,
    title: 'Card details',
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecretLabel(label: 'Card number', value: '4242 4242 4242 4242'),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _SecretLabel(label: 'Expires', value: '12 / 30'),
            ),
            Expanded(
              child: _SecretLabel(label: 'CVC', value: '737'),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Future<void> showPin(BuildContext context, {required String cardId}) => _show(
    context,
    title: 'Card PIN',
    child: const _SecretLabel(label: 'PIN', value: '2048'),
  );

  Future<void> _show(
    BuildContext context, {
    required String title,
    required Widget child,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ScreenshotSensitive(
      child: AlertDialog(
        title: Text(title),
        content: Semantics(
          container: true,
          explicitChildNodes: true,
          child: child,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hide'),
          ),
        ],
      ),
    ),
  );
}

class _SecretLabel extends StatelessWidget {
  const _SecretLabel({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 1.2,
        ),
      ),
    ],
  );
}
