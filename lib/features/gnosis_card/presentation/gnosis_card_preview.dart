import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_secure_element_gateway.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_page.dart';

@Preview(
  name: 'Card dashboard · phone · light',
  group: 'Gnosis Pay cards',
  size: Size(390, 844),
  brightness: Brightness.light,
)
@Preview(
  name: 'Card dashboard · desktop · dark',
  group: 'Gnosis Pay cards',
  size: Size(1280, 900),
  brightness: Brightness.dark,
)
Widget gnosisCardDashboardPreview() {
  return buildGnosisCardPreview();
}

Widget buildGnosisCardPreview({ThemeMode themeMode = ThemeMode.system}) {
  const config = GnosisCardConfig(
    mode: GnosisCardMode.mock,
    scenario: GnosisCardScenario.happyPath,
    failureReason: null,
  );
  final dependencies = GnosisCardDependencies.forAdapters(
    config: config,
    secureElement: const SyntheticSecureElementGateway(),
  );
  return RepositoryProvider.value(
    value: dependencies,
    child: BlocProvider(
      create: (_) => GnosisCardBloc(
        config: config,
        coordinator: null,
        initialState: GnosisCardState(
          status: GnosisCardLoadStatus.ready,
          snapshot: gnosisCardPreviewSnapshot(),
        ),
      ),
      child: MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: themeMode,
        home: const Scaffold(
          body: RepaintBoundary(
            key: Key('gnosis-card-preview'),
            child: _PreviewCanvas(),
          ),
        ),
      ),
    ),
  );
}

class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas();

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: const GnosisCardPage(),
    ),
  );
}

GnosisCardSnapshot gnosisCardPreviewSnapshot() => GnosisCardSnapshot(
  stage: GnosisOnboardingStage.ready,
  deployment: const SafeDeployment(
    requestId: 'preview',
    status: SafeDeploymentStatus.ok,
    safeAddress: '0x1111111111111111111111111111111111111111',
    delayModule: '0x2222222222222222222222222222222222222222',
  ),
  dashboard: GnosisCardDashboard(
    balanceMinor: 184250,
    currency: 'EUR',
    dailyLimitMinor: 150000,
    cards: const [
      GnosisPaymentCard(
        id: 'preview-card',
        kind: GnosisCardKind.virtual,
        status: GnosisCardStatus.active,
        lastFour: '4242',
        label: 'Everyday card',
      ),
    ],
    controls: const GnosisCardControls(
      contactless: true,
      online: true,
      atm: false,
    ),
    transactions: [
      GnosisCardTransaction(
        id: 'preview-tx',
        merchant: 'City Market',
        amountMinor: -4235,
        currency: 'EUR',
        occurredAt: DateTime(2026, 7, 9, 17, 42),
        isDeclined: false,
      ),
    ],
    operations: const [],
  ),
);
