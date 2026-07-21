import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_coordinator.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/deterministic_gnosis_pay_repository.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';

part 'gnosis_card_flow_happy_path_test.dart';
part 'gnosis_card_flow_recovery_test.dart';
part 'gnosis_card_flow_test_support.dart';

void main() {
  group('mock-first Gnosis card onboarding', () {
    _registerHappyPathFlowTests();
    _registerFlowRecoveryTests();
  });
}
