import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/nft_receive/bloc/nft_receive_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';
import 'package:web_dex/views/nfts/nft_receive/nft_receive_view.dart';

/// Hosts the NFT receive flow behind the shared seed-backup gate.
///
/// The gate used to live inside `NftReceiveBloc`, which is why it only ever
/// covered this one screen while every other receive surface was open. A bloc
/// emitting "render the backup banner" is UI policy in the wrong layer; keeping
/// it here means NFT receive is gated by exactly the same rule as everything
/// else.
class NftReceivePage extends StatefulWidget {
  const NftReceivePage({super.key});

  @override
  State<NftReceivePage> createState() => _NftReceivePageState();
}

class _NftReceivePageState extends State<NftReceivePage> {
  bool _checkedGate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGate());
  }

  Future<void> _runGate() async {
    // NFTs are EVM-mainnet only here, so there is no test-coin exemption to
    // thread through - unlike the per-asset receive paths.
    final mayReveal = await ensureSeedBackedUp(
      context,
      reason: SeedBackupGateReason.nftReceive,
    );
    if (!mounted) return;
    if (!mayReveal) {
      routingState.nftsState.reset();
      return;
    }
    setState(() => _checkedGate = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedGate) return const SizedBox.shrink();

    return BlocBuilder<NftMainBloc, NftMainState>(
      builder: (context, state) {
        return BlocProvider(
          create: (context) => NftReceiveBloc(
            coinsRepo: RepositoryProvider.of<CoinsRepo>(context),
            sdk: RepositoryProvider.of<KomodoDefiSdk>(context),
          )..add(NftReceiveStarted(chain: state.selectedChain)),
          child: NftReceiveView(),
        );
      },
    );
  }
}
