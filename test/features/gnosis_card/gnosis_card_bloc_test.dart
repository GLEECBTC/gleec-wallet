import 'package:bloc_test/bloc_test.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

void main() {
  blocTest<GnosisCardBloc, GnosisCardState>(
    'fails closed when card mode is disabled',
    build: () => GnosisCardBloc(
      config: const GnosisCardConfig(
        mode: GnosisCardMode.disabled,
        scenario: GnosisCardScenario.happyPath,
        failureReason: 'Disabled for test',
      ),
      coordinator: null,
    ),
    act: (bloc) => bloc.add(const GnosisCardStarted()),
    expect: () => const [
      GnosisCardState(
        status: GnosisCardLoadStatus.disabled,
        message: 'Disabled for test',
      ),
    ],
  );
}
