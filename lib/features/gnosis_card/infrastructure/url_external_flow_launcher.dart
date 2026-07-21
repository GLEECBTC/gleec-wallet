import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/shared/utils/utils.dart';

/// Opens Gnosis-owned content outside the wallet UI.
///
/// Flow URLs can contain short-lived third-party state, so failures deliberately
/// avoid including the URL in messages or logs.
class UrlExternalFlowLauncher implements ExternalFlowLauncher {
  const UrlExternalFlowLauncher();

  @override
  Future<void> launch(GnosisExternalFlow flow) async {
    final uri = Uri.tryParse(flow.url);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidInput,
        message:
            'The secure external onboarding link is invalid. Refresh and retry.',
        recovery: GnosisCardRecovery.retry,
      );
    }

    try {
      await openUrl(uri, inSeparateTab: true);
    } catch (_) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.unavailable,
        message: 'The external onboarding page could not be opened.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }
}
