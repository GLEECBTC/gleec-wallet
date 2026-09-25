import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/shared/widgets/nft/nft_badge.dart';
import 'package:web_dex/views/wallet/coin_details/receive/qr_code_address.dart';
import 'package:web_dex/views/wallet/coin_details/receive/receive_address.dart';

enum NftReceiveCardAlignment { top, bottom }

class NftReceiveCard extends StatelessWidget {
  const NftReceiveCard({
    required this.currentAddress,
    required this.qrCodeSize,
    required this.onAddressChanged,
    required this.coin,
    required this.pubkeys,
    this.maxWidth = 343,
    super.key,
  });

  final PubkeyInfo? currentAddress;
  final AssetPubkeys pubkeys;
  final double qrCodeSize;
  final void Function(PubkeyInfo?) onAddressChanged;
  final Asset coin;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).extension<ColorSchemeExtension>()!;
    final textTheme = Theme.of(context).extension<TextThemeExtension>()!;
    final address = currentAddress;
    final chain = fromCoinToChain(coin);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.surfContLow,
      ),
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                LocaleKeys.network.tr(),
                style: textTheme.bodyS,
              ),
              if (chain != null) BlockchainBadge(blockchain: chain),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            LocaleKeys.scanToGetAddress.tr(),
            style: textTheme.bodyS,
          ),
          const SizedBox(height: 16),
          if (address != null)
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10.0),
                  width: qrCodeSize,
                  height: qrCodeSize,
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.surfContHighest),
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: BlocSelector<SettingsBloc, SettingsState, ThemeMode>(
                    selector: (state) => state.themeMode,
                    builder: (context, state) {
                      final isDarkTheme = state == ThemeMode.dark;
                      final Color foregroundColor =
                          isDarkTheme ? Colors.white : Colors.black;
                      final Color backgroundColor =
                          isDarkTheme ? colorScheme.surfContLow : Colors.white;

                      return QRCodeAddress(
                        currentAddress: address.address,
                        borderRadius: BorderRadius.circular(0),
                        padding: EdgeInsets.zero,
                        backgroundColor: backgroundColor,
                        foregroundColor: foregroundColor,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  LocaleKeys.ercStandardDisclaimer.tr(),
                  style: textTheme.bodyXS.copyWith(color: colorScheme.orange),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ReceiveAddress(
                  asset: coin,
                  selectedAddress: address,
                  pubkeys: pubkeys,
                  onChanged: onAddressChanged,
                  backgroundColor: colorScheme.surfContHighest,
                ),
                if (!address.isActiveForSwap) ...[
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: colorScheme.orange.withOpacity(0.15),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.orange,
                        size: 28,
                      ),
                      title: Text(
                        LocaleKeys.nftReceiveNonSwapAddressWarning.tr(),
                        style: textTheme.bodyM.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.orange,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          LocaleKeys.nftReceiveNonSwapWalletDetails.tr(),
                          style: textTheme.bodyS,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  NftBlockchains? fromCoinToChain(Asset coin) {
    switch (coin.id.id) {
      case 'ETH':
        return NftBlockchains.eth;
      case 'BNB':
        return NftBlockchains.bsc;
      case 'AVAX':
        return NftBlockchains.avalanche;
      case 'POL':
        return NftBlockchains.polygon;
      case 'FTM':
        return NftBlockchains.fantom;
      default:
        return null;
    }
  }
}
