import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
import 'package:web_dex/shared/utils/extensions/sdk_extensions.dart';
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
  return state.addresses
      .where((address) => address.gasfreeAddress?.isNotEmpty ?? false)
      .fold(Decimal.zero, (sum, address) => sum + address.balance.spendable);
}

/// Amber disclosure shown on the coin-details page when a gasless asset holds
/// funds on its standard (EOA) address — e.g. an exchange that refuses
/// contract addresses paid out to the standard address.
///
/// Offers the one-tap "Move to gasless address" consolidation: a one-time
/// native transfer into the user's own custody address. This is deliberately
/// the ONLY surface in the gasless UX that mentions needing TRX.
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
    if (!coin.isGaslessAsset(context.sdk)) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<CoinAddressesBloc, CoinAddressesState>(
      builder: (context, state) {
        final stranded = strandedStandardBalance(state);
        if (stranded <= Decimal.zero) {
          return const SizedBox.shrink();
        }

        final parentId = coin.id.parentId;

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
            footer: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('gasless-consolidate-button'),
                onPressed: () => setPageType(CoinPageType.sendConsolidate),
                child: Text(
                  LocaleKeys.gaslessStandardBalanceAction.tr(),
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
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
                  LocaleKeys.gaslessStandardBalanceBody.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
                if (parentId != null)
                  _ZeroTrxWarning(parentId: parentId, foreground: foreground),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pre-warns when the move cannot be sent yet: the consolidation is a native
/// transfer whose fee needs TRX on the standard address. Watches the parent
/// (TRX) balance so the warning clears as soon as a top-up lands; when the
/// balance is unknown the warning is omitted rather than guessed. The button
/// stays enabled: the withdraw form's native-rail guard remains the
/// enforcement backstop.
class _ZeroTrxWarning extends StatelessWidget {
  const _ZeroTrxWarning({required this.parentId, required this.foreground});

  final AssetId parentId;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final balances = context.sdk.balances;
    return StreamBuilder<BalanceInfo>(
      stream: balances.watchBalance(parentId, activateIfNeeded: false),
      initialData: balances.lastKnown(parentId),
      builder: (context, snapshot) {
        final balance = snapshot.data;
        if (balance == null || balance.spendable > Decimal.zero) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            LocaleKeys.gaslessStandardBalanceNoTrxWarning.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}
