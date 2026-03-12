import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/nft_transactions/bloc/nft_transactions_filters.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/rpc/nft_transaction/nft_transactions_response.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/views/nfts/nft_transactions/mobile/widgets/nft_txn_mobile_filter_card.dart';

class NftTxnMobileFilters extends StatefulWidget {
  final NftTransactionsFilter filters;
  final void Function(NftTransactionsFilter?) onApply;

  const NftTxnMobileFilters({required this.filters, required this.onApply});

  @override
  State<NftTxnMobileFilters> createState() => _NftTxnMobileFiltersState();
}

class _NftTxnMobileFiltersState extends State<NftTxnMobileFilters> {
  final List<NftTransactionStatuses> statuses = [];
  final List<NftBlockchains> blockchains = [];
  DateTime? dateFrom;
  DateTime? dateTo;

  final DateFormat dateFormatter = DateFormat('dd MMMM yyyy', 'en_US');

  @override
  void initState() {
    setState(() {
      statuses.addAll(widget.filters.statuses);
      blockchains.addAll(widget.filters.blockchain);
      dateFrom = widget.filters.dateFrom;
      dateTo = widget.filters.dateTo;
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    const gridDelete = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
      mainAxisExtent: 56,
    );

    final bool isButtonDisabled =
        statuses.isEmpty &&
        blockchains.isEmpty &&
        dateFrom == null &&
        dateTo == null;

    return Theme(
      data: Theme.of(context).brightness == Brightness.light
          ? newThemeLight
          : newThemeDark,
      child: Builder(
        builder: (context) {
          final colorScheme = Theme.of(
            context,
          ).extension<ColorSchemeExtension>();
          final textScheme = Theme.of(context).extension<TextThemeExtension>();
          return Container(
            decoration: BoxDecoration(
              color: colorScheme?.surfContLowest,
              border: Border.all(
                color: colorScheme?.s40 ?? Colors.transparent,
                width: 1,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: ScrollController(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme?.surf,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(LocaleKeys.filters.tr(), style: textScheme?.bodyMBold),
                  const SizedBox(height: 24),
                  GridView(
                    gridDelegate: gridDelete,
                    shrinkWrap: true,
                    children: [
                      NftTxnMobileFilterCard(
                        title: LocaleKeys.send.tr(),
                        onTap: () {
                          setState(() {
                            statuses.contains(NftTransactionStatuses.send)
                                ? statuses.remove(NftTransactionStatuses.send)
                                : statuses.add(NftTransactionStatuses.send);
                          });
                          widget.onApply(getFilters());
                        },
                        isSelected: statuses.contains(
                          NftTransactionStatuses.send,
                        ),
                        svgPath: '$assetsPath/custom_icons/send.svg',
                      ),
                      NftTxnMobileFilterCard(
                        title: LocaleKeys.receive.tr(),
                        onTap: () {
                          setState(() {
                            statuses.contains(NftTransactionStatuses.receive)
                                ? statuses.remove(
                                    NftTransactionStatuses.receive,
                                  )
                                : statuses.add(NftTransactionStatuses.receive);
                          });
                          widget.onApply(getFilters());
                        },
                        isSelected: statuses.contains(
                          NftTransactionStatuses.receive,
                        ),
                        svgPath: '$assetsPath/custom_icons/receive.svg',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(LocaleKeys.blockchain.tr(), style: textScheme?.bodyM),
                  const SizedBox(height: 8),
                  GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: gridDelete,
                    itemBuilder: (context, index) {
                      final NftBlockchains blockchain =
                          NftBlockchains.values[index];
                      final chainColor = _getChainColor(blockchain);
                      return NftTxnMobileFilterCard(
                        onTap: () {
                          setState(() {
                            blockchains.contains(blockchain)
                                ? blockchains.remove(blockchain)
                                : blockchains.add(blockchain);
                          });
                          widget.onApply(getFilters());
                        },
                        title: blockchain.toString(),
                        isSelected: blockchains.contains(blockchain),
                        accentColor: chainColor,
                        svgPath:
                            '$assetsPath/blockchain_icons/svg/32px/${blockchain.toApiRequest().toLowerCase()}.svg',
                      );
                    },
                    itemCount: NftBlockchains.values.length,
                  ),
                  const SizedBox(height: 20),
                  Text(LocaleKeys.date.tr(), style: textScheme?.bodyM),
                  const SizedBox(height: 8),
                  GridView(
                    gridDelegate: gridDelete,
                    shrinkWrap: true,
                    children: [
                      UiDatePicker(
                        formatter: dateFormatter.format,
                        isMobileAlternative: true,
                        date: dateFrom,
                        text: LocaleKeys.fromDate.tr(),
                        endDate: dateTo,
                        onDateSelect: (time) {
                          setState(() {
                            dateFrom = time;
                          });
                          widget.onApply(getFilters());
                        },
                      ),
                      UiDatePicker(
                        formatter: dateFormatter.format,
                        isMobileAlternative: true,
                        date: dateTo,
                        text: LocaleKeys.toDate.tr(),
                        startDate: dateFrom,
                        onDateSelect: (time) {
                          setState(() {
                            dateTo = time;
                          });
                          widget.onApply(getFilters());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Flexible(
                    child: UiPrimaryButton(
                      border: Border.all(
                        color: colorScheme?.secondary ?? Colors.transparent,
                        width: 2,
                      ),
                      backgroundColor: Colors.transparent,
                      height: 40,
                      text: LocaleKeys.clearFilter.tr(),
                      onPressed: isButtonDisabled
                          ? null
                          : () {
                              setState(() {
                                statuses.clear();
                                blockchains.clear();
                                dateFrom = null;
                                dateTo = null;
                              });
                              widget.onApply(getFilters());
                            },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  NftTransactionsFilter getFilters() {
    return NftTransactionsFilter(
      statuses: statuses,
      blockchain: blockchains,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  Color _getChainColor(NftBlockchains chain) {
    switch (chain) {
      case NftBlockchains.eth:
        return const Color(0xFF3D77E9);
      case NftBlockchains.bsc:
        return const Color(0xFFE6BC41);
      case NftBlockchains.avalanche:
        return const Color(0xFFD54F49);
      case NftBlockchains.polygon:
        return const Color(0xFF7B49DD);
      case NftBlockchains.fantom:
        return const Color(0xFF3267F6);
    }
  }
}
