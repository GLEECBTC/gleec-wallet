import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/gasless/tron_gasless_consolidation_gate.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';

/// Total token balance sitting on the standard (EOA) addresses of [coin].
///
/// For a gasless asset the app receives into — and spends from — the GasFree
/// custody address, so any standard-address balance is stranded: it cannot be
/// sent gaslessly and would otherwise be invisible (the headline balance shows
/// custody only). `PubkeyInfo.balance` is the raw EOA balance — the custody
/// substitution in the SDK's BalanceManager does not touch pubkeys.
Decimal strandedStandardBalance(CoinAddressesState state) {
  return state.addresses.fold(
    Decimal.zero,
    (sum, address) => sum + address.balance.total,
  );
}

/// Amber disclosure shown on the coin-details page when a gasless asset holds
/// funds on its standard (EOA) address — e.g. an exchange that refuses
/// contract addresses paid out to the standard address.
///
/// Opens the per-source "Move to gasless address" wizard. Each funded EOA is
/// reviewed independently because only TRX on that exact derivation can pay
/// its native network fee. This is deliberately the only GasFree surface that
/// asks a user to fund TRX.
class GaslessStandardBalanceNotice extends StatelessWidget {
  const GaslessStandardBalanceNotice({
    required this.coin,
    required this.setPageType,
    super.key,
  });

  final Coin coin;
  final void Function(CoinPageType) setPageType;

  @override
  Widget build(BuildContext context) {
    // Recovery must remain visible when either production kill switch is
    // disabled. These are already-owned Standard funds, not a request to
    // expose a new custody receive address.
    if (!coin.isGaslessRecoveryAsset) {
      return const SizedBox.shrink();
    }

    final sdk = context.read<KomodoDefiSdk>();
    final walletType = context.select<AuthBloc, WalletType?>(
      (bloc) => bloc.state.currentUser?.wallet.config.type,
    );

    return BlocBuilder<CoinAddressesBloc, CoinAddressesState>(
      builder: (context, state) {
        final stranded = strandedStandardBalance(state);
        if (stranded <= Decimal.zero) {
          return const SizedBox.shrink();
        }

        final asset = sdk.assets.fromId(coin.id);
        final consolidationAddress = asset == null
            ? null
            : verifiedTronGaslessConsolidationAddress(
                sdk,
                asset,
                state,
                walletType: walletType,
              );
        final canMoveToGasfree = consolidationAddress != null;

        final theme = Theme.of(context);
        final foreground = NoticeBanner.styleOf(
          context,
          NoticeBannerVariant.warning,
        ).foreground;

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: NoticeBanner(
            key: const Key('gasless-standard-balance-notice'),
            icon: Icons.account_balance_wallet_outlined,
            footer: canMoveToGasfree
                ? Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('gasless-consolidate-button'),
                      onPressed: () {
                        if (asset == null) return;
                        final currentState = context
                            .read<CoinAddressesBloc>()
                            .state;
                        if (verifiedTronGaslessConsolidationAddress(
                              sdk,
                              asset,
                              currentState,
                              walletType: context
                                  .read<AuthBloc>()
                                  .state
                                  .currentUser
                                  ?.wallet
                                  .config
                                  .type,
                            ) ==
                            null) {
                          return;
                        }
                        setPageType(CoinPageType.sendConsolidate);
                      },
                      child: Text(
                        LocaleKeys.gaslessStandardBalanceAction.tr(),
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.gaslessStandardBalanceTitle.tr(
                    args: [formatDexAmt(stranded), coin.abbr],
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (canMoveToGasfree
                          ? LocaleKeys.gaslessStandardBalanceBody
                          : LocaleKeys.receiveGaslessPausedNotice)
                      .tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
