# Unlocalized Text Inventory

Generated: 2026-02-04

## Scope & notes
- Scope: UI-facing text in `lib/views`, `lib/shared/widgets`, `lib/shared/ui`, `lib/sdk/widgets`, `lib/services/feedback`, plus UI kit defaults in `packages/komodo_ui_kit` and user-facing error/validator strings in `lib/bloc`.
- Excludes: tests, asset paths/keys, analytics-only strings, and debug logs.
- Some entries are formatting around localized strings (counts, colons, slashes, punctuation). Those are still listed because they hardcode English punctuation/ordering.

## Global dialogs & feedback
- `lib/sdk/widgets/window_close_handler.dart:109` — "Do you really want to quit?"
- `lib/sdk/widgets/window_close_handler.dart:116` — "Cancel"
- `lib/sdk/widgets/window_close_handler.dart:120` — "Yes"
- `lib/shared/utils/window/window_native.dart:38` — "Cancel"
- `lib/shared/utils/window/window_native.dart:42` — "OK"
- `lib/shared/utils/utils.dart:72` — "Failed to copy to clipboard"
- `lib/services/feedback/feedback_ui_extension.dart:112` — "Let's Connect on Discord!"
- `lib/services/feedback/feedback_ui_extension.dart:153` — "Close"
- `lib/services/feedback/feedback_ui_extension.dart:162` — "Join Komodo Discord"
- `lib/views/main_layout/main_layout.dart:192` — "Report a bug or feedback"

## Settings & support
- `lib/views/settings/widgets/general_settings/app_version_number.dart:49` — "Error: ${state.message}"
- `lib/views/settings/widgets/general_settings/app_version_number.dart:101` — "$label:" (localized label + colon)
- `lib/views/settings/widgets/support_page/support_page.dart:101` — "https://www.gleec.com/contact"

## Fiat
- `lib/views/fiat/fiat_tab_bar.dart:44` — "Form"
- `lib/views/fiat/fiat_tab_bar.dart:50` — "In Progress"
- `lib/views/fiat/fiat_tab_bar.dart:56` — "History"
- `lib/views/fiat/fiat_inputs.dart:167` — "${LocaleKeys.enterAmount.tr()} $boundariesString" (localized label + bounds)

## NFTs
- `lib/views/nfts/common/widgets/nft_no_chains_enabled.dart:15` — "Please enable NFT protocol assets in the wallet. Enable chains like ETH, BNB, AVAX, MATIC, or FTM to view your NFTs."
- `lib/views/nfts/nft_transactions/desktop/widgets/nft_txn_desktop_filters.dart:83` — "Status"
- `lib/views/nfts/nft_transactions/desktop/widgets/nft_txn_desktop_filters.dart:96` — "Blockchain"
- `lib/views/nfts/nft_transactions/common/widgets/nft_txn_media.dart:45` — "-" (fallback title)
- `lib/views/nfts/nft_transactions/common/widgets/nft_txn_media.dart:49` — " ($amount)"
- `lib/views/nfts/nft_transactions/common/utils/formatter.dart:7` — `NumberFormat("##0.00#####", "en_US")`
- `lib/views/nfts/nft_transactions/common/utils/formatter.dart:9` — "-"
- `lib/views/nfts/nft_transactions/common/utils/formatter.dart:17` — "-"
- `lib/views/nfts/nft_transactions/common/utils/formatter.dart:18` — "-"
- `lib/views/nfts/nft_transactions/common/utils/formatter.dart:21` — "-"
- `lib/views/nfts/nft_transactions/common/utils/formatter.dart:23` — `NumberFormat.decimalPatternDigits(locale: "en_US", ...)` and "USD"
- `lib/views/nfts/nft_tabs/nft_tab.dart:105` — "Ethereum"
- `lib/views/nfts/nft_tabs/nft_tab.dart:107` — "BNB Smart Chain"
- `lib/views/nfts/nft_tabs/nft_tab.dart:109` — "Avalanche C-Chain"
- `lib/views/nfts/nft_tabs/nft_tab.dart:111` — "Polygon"
- `lib/views/nfts/nft_tabs/nft_tab.dart:113` — "Fantom"

## Bitrefill
- `lib/views/bitrefill/bitrefill_button.dart:120` — "${widget.coin.abbr} is currently suspended"
- `lib/views/bitrefill/bitrefill_button.dart:124` — "${widget.coin.abbr} is not supported by Bitrefill"
- `lib/views/bitrefill/bitrefill_button.dart:128` — "No ${widget.coin.abbr} balance available for spending"

## Wallet: main lists & balances
- `lib/views/wallet/wallet_page/wallet_main/all_coins_list.dart:64` — "No coins found"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:197` — "Maximum gap limit reached - please use existing unused addresses first"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:199` — "Maximum number of addresses reached for this asset"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:201` — "Missing derivation path configuration"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:203` — "Protocol does not support multiple addresses"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:205` — "Current wallet mode does not support multiple addresses"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:207` — "No active wallet - please sign in first"
- `lib/views/wallet/wallet_page/wallet_main/active_coins_list.dart:272` — "Derivation: ${pubkey.derivationPath}"
- `lib/views/wallet/wallet_page/wallet_main/balance_summary_widget.dart:50` — "\$${maskedBalanceText}"
- `lib/views/wallet/wallet_page/wallet_main/balance_summary_widget.dart:51` — "\$${NumberFormat(\"#,##0.00\").format(totalBalance!)}"
- `lib/views/wallet/wallet_page/wallet_main/balance_summary_widget.dart:64` — `NumberFormat.currency(symbol: '$')`
- `lib/shared/constants.dart:36` — "****" (masked balance)
- `lib/shared/widgets/coin_balance.dart:36` — "--"
- `lib/shared/widgets/coin_balance.dart:51` — " ${Coin.normalizeAbbr(coin.abbr)}"

## Wallet: list items & tooltips
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:206` — "${displayCount} key${displayCount > 1 ? 's' : ''}"
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:239` — "${displayCount} key${displayCount > 1 ? 's' : ''}"
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:320` — "Path"
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:349` — "Copy address"
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:374` — "Copy pubkey"
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:381` — "Private key"
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:387` — "*" (mask character)
- `lib/views/wallet/wallet_page/common/expandable_private_key_list.dart:498` — "Path: ${widget.privateKey.hdInfo!.derivationPath}"
- `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart:167` — "${doubleToString(...)} ${widget.coin.abbr}"
- `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart:217` — `NumberFormat.currency(symbol: '$')`
- `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart:304` — "\$${maskedBalanceText}"
- `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart:316` — "--"
- `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart:319` — "\$$formatted"
- `lib/views/wallet/wallet_page/common/expandable_coin_list_item.dart:399` — "${doubleToString(...)} ${coin.abbr}"
- `lib/views/wallet/wallet_page/common/grouped_asset_ticker_item.dart:79` — `NumberFormat.currency(symbol: '$')`
- `lib/views/wallet/wallet_page/common/grouped_asset_ticker_item.dart:223` — "Hide related assets"
- `lib/views/wallet/wallet_page/common/grouped_asset_ticker_item.dart:224` — "Show related assets"
- `lib/views/wallet/wallet_page/common/grouped_asset_ticker_item.dart:258` — "Available on Networks:"
- `lib/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_dialog.dart:111` — "1000" (default blocks per iter)
- `lib/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_dialog.dart:112` — "200" (default interval ms)
- `lib/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_dialog.dart:586` — "Download timed out after ${downloadTimeout.inMinutes} minutes"

## Wallet: charts & formatting
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:66` — `symbol: '$'`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:69` — "--"
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:100` — "Error: ${state.error}"
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:217` — `DateFormat("MMM")`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:222` — `DateFormat("MMM ''yy")`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:227` — `DateFormat("MMM d")`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:235` — `DateFormat("d")`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:242` — `DateFormat("EEE")`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:249` — `DateFormat("EEE HH:mm")`
- `lib/views/wallet/wallet_page/charts/coin_prices_chart.dart:255` — `DateFormat("HH:mm")`
- `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart:23` — "--"
- `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart:26` — "\$${value.toStringAsFixed(2)}"
- `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart:28` — "\$${value.toStringAsPrecision(4)}"
- `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart:47` — "MMMM d, y"
- `lib/views/wallet/wallet_page/charts/price_chart_tooltip.dart:63` — "${coin.name}: ${valueToString(...)}"

## Coin details & info
- `lib/shared/widgets/coin_type_tag.dart:46` — "SMART CHAIN"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_info_fiat.dart:83` — "\$"
- `lib/views/wallet/coin_details/coin_details_info/coin_addresses.dart:319` — "${maskedBalanceText} ${abbr2Ticker(coin.abbr)} ($fiat)"
- `lib/views/wallet/coin_details/coin_details_info/coin_addresses.dart:320` — "${doubleToString(balance)} ${abbr2Ticker(coin.abbr)} ($fiat)"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart:341` — "${address.balance.spendable} ${coin.displayName} available"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart:444` — "${coin.abbr} is currently suspended"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart:471` — "Asset ${coin.id.id} not found"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart:494` — "Error updating configuration: $e"
- `lib/views/wallet/coin_details/coin_details_info/charts/coin_sparkline.dart:24` — "Error: ${snapshot.error}"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart:96` — `symbol: '$'`
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart:149` — `locale: 'en_US'`
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart:187` — "Linear progress indicator"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart:245` — "MMMM d, y"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart:281` — `symbol: '$'`
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:83` — `NumberFormat.currency(symbol: '$', ...)`
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:84` — "--"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:145` — `locale: 'en_US'`
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:181` — "Linear progress indicator"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:202` — "USDT"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:232` — "MMMM d, y"
- `lib/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart:237` — `NumberFormat.currency(symbol: '$', ...)`
- `lib/views/wallet/coin_details/coin_details_info/charts/animated_portfolio_charts.dart:79-84` — time unit suffixes "y", "M", "d", "h", "m", "s"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart:79` — "USDT"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart:89` — "USDT"
- `lib/views/wallet/coin_details/coin_details_info/coin_details_info.dart:455-460` — time unit suffixes "y", "M", "d", "h", "m", "s"
- `lib/views/wallet/coin_details/transactions/transaction_list_item.dart:126` — "$formatted ${Coin.normalizeAbbr(...)} "
- `lib/views/wallet/coin_details/transactions/transaction_list_item.dart:289` — "$_sign \$${formatAmt(...)}"
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:109` — "+KMD "
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:117` — "+KMD "
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:131` — "-"
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:186` — "-"
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:208` — "${dd} day(s)"
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:213` — "${hh}h ${minutes}m"
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:216` — "${mm}min"
- `lib/views/wallet/coin_details/rewards/kmd_reward_list_item.dart:218` — "-"
- `lib/views/wallet/coin_details/rewards/kmd_reward_info_header.dart:73` — "coingecko.com"
- `lib/views/wallet/coin_details/rewards/kmd_reward_info_header.dart:82` — "openrates.io"
- `lib/views/wallet/coin_details/rewards/kmd_reward_claim_success.dart:62` — "\$${formattedUsd}"
- `lib/views/wallet/coin_details/faucet/widgets/faucet_message.dart:33` — "${info.message}\n" (API-provided message)

## Withdraw flow
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:36` — "Please enter recipient address"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:40` — "Recipient Address"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:41` — "Enter recipient address"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:78` — "Please enter an amount"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:81` — "Please enter a valid number"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:83` — "Amount must be greater than 0"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:87` — "Amount"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:88` — "Enter amount to send"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:189` — "Gas Price (Gwei)"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:206` — "Higher gas price = faster confirmation"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:210` — "Gas Limit"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:212` — "21000" (default gas limit)
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:227` — "Estimated: 21000"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:255` — "Standard ($defaultFee)"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:259` — "Fast (${defaultFee * 2})"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:263` — "Urgent (${defaultFee * 5})"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:282` — "Higher fee = faster confirmation"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:313` — "From"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:316` — "Default Wallet"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:320` — "To"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:325` — "Amount"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:331` — "Network Fee"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:336` — "Memo"
- `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart:466` — "Withdrawal Failed"
- `lib/views/wallet/coin_details/withdraw_form/withdraw_form.dart:127` — "Since you're sending your full amount, the network fee will be deducted from the amount. Do you agree?"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form.dart:53` — "-${state.amount} ${Coin.normalizeAbbr(state.asset.id.id)}"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form.dart:62` — "\$${state.usdAmountPrice ?? 0}"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form.dart:134` — "${LocaleKeys.fee.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form.dart:143` — "${LocaleKeys.transactionHash.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_complete_form/send_complete_form.dart:169` — "${LocaleKeys.memo.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form.dart:47` — "${LocaleKeys.recipientAddress.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form.dart:53` — "${LocaleKeys.amount.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form.dart:59` — "${LocaleKeys.fee.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form.dart:68` — "${LocaleKeys.memo.tr()}:"
- `lib/views/wallet/coin_details/withdraw_form/widgets/send_confirm_form/send_confirm_form_error.dart:18` — "Unknown error"

## DEX
- `lib/views/dex/dex_helpers.dart:54` — "≈\$${formatAmt(...)}"
- `lib/views/dex/dex_helpers.dart:345` — "\$0.00"
- `lib/views/dex/dex_list_filter/mobile/dex_list_filter_coins_list_mobile.dart:163` — " (segwit)"
- `lib/views/dex/dex_list_filter/mobile/dex_list_filter_coins_list_mobile.dart:167` — "($pairCount)"
- `lib/views/dex/dex_list_filter/mobile/dex_list_filter_mobile.dart:98` — "${LocaleKeys.taker.tr()}/${LocaleKeys.maker.tr()}"
- `lib/views/dex/dex_list_filter/desktop/dex_list_filter_desktop.dart:152` — "${LocaleKeys.taker.tr()}/${LocaleKeys.maker.tr()}"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:33` — "${LocaleKeys.rate.tr()}:"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:37` — "0.00"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:74` — " 1 ${Coin.normalizeAbbr(base ?? '')} = "
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:79` — " $price ${Coin.normalizeAbbr(rel ?? '')}"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:84` — "(${baseFiat(context)})"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:91-94` — "1 ${Coin.normalizeAbbr(rel ?? '')} = $quotePrice ${Coin.normalizeAbbr(base ?? '')} (${relFiat(context)})"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:118` — "0"
- `lib/views/dex/simple/form/exchange_info/exchange_rate.dart:123` — "0"
- `lib/views/dex/simple/form/exchange_info/dex_compared_to_cex.dart:77` — "${formatAmt(diff)}%"
- `lib/views/dex/simple/form/tables/orders_table/grouped_list_view.dart:176` — " $abbr"
- `lib/views/dex/orderbook/orderbook_table.dart:84` — " ≈ "
- `lib/views/dex/orderbook/orderbook_table.dart:85` — "\$$baseUsdPrice"
- `lib/views/dex/common/trading_amount_field.dart:40` — "0.00"
- `lib/views/dex/simple/form/maker/maker_form_buy_amount.dart:103` — "0.00"
- `lib/views/dex/simple/form/maker/maker_form_sell_amount.dart:109` — "0.00"

## Market maker bot
- `lib/views/market_maker_bot/coin_search_dropdown.dart:40` — "Search coins"
- `lib/views/market_maker_bot/coin_search_dropdown.dart:46` — "Search coins"
- `lib/views/market_maker_bot/coin_search_dropdown.dart:247` — "Search"
- `lib/views/market_maker_bot/coin_trade_amount_form_field.dart:130` — "≈$0"
- `lib/views/market_maker_bot/coin_trade_amount_form_field.dart:172` — "0.00"
- `lib/views/market_maker_bot/coin_trade_amount_form_field.dart:182` — "*"
- `lib/views/market_maker_bot/coin_trade_amount_label.dart:72` — "≈$0"
- `lib/views/market_maker_bot/coin_trade_amount_label.dart:110` — "*"
- `lib/views/market_maker_bot/market_maker_form_error_message_extensions.dart:98` — "too low for ${baseCoin?.abbr ?? ''}"
- `lib/views/market_maker_bot/market_maker_form_error_message_extensions.dart:115` — "too low for"
- `lib/views/market_maker_bot/trade_volume_type.dart:9` — "\$" and "%"
- `lib/views/market_maker_bot/trade_volume_type.dart:11` — "USD" and "Percentage"
- `lib/views/market_maker_bot/trade_pair_list_item.dart:38` — "-" (date placeholder)
- `lib/views/market_maker_bot/trade_pair_list_item.dart:74` — "${config.margin.toStringAsFixed(2)}%"
- `lib/views/market_maker_bot/trade_pair_list_item.dart:75` — "${config.updateInterval.minutes} min"
- `lib/views/market_maker_bot/trade_bot_update_interval.dart:10` — "1"
- `lib/views/market_maker_bot/trade_bot_update_interval.dart:12` — "3"
- `lib/views/market_maker_bot/trade_bot_update_interval.dart:14` — "5"
- `lib/views/market_maker_bot/trade_bot_update_interval.dart:33` — "Invalid interval"
- `lib/views/market_maker_bot/update_interval_dropdown.dart:38` — "${interval.minutes} ${LocaleKeys.minutes.tr()}"
- `lib/views/market_maker_bot/market_maker_bot_tab_type.dart:19` — "${LocaleKeys.orders.tr()} (${bloc.tradeBotOrdersCount})"
- `lib/views/market_maker_bot/market_maker_bot_tab_type.dart:21` — "${LocaleKeys.inProgress.tr()} (${bloc.inProgressCount})"
- `lib/views/market_maker_bot/market_maker_bot_tab_type.dart:23` — "${LocaleKeys.history.tr()} (${bloc.completedCount})"
- `lib/views/market_maker_bot/market_maker_bot_form_content.dart:101` — "${LocaleKeys.margin.tr()}:"
- `lib/views/market_maker_bot/market_maker_bot_form_content.dart:116` — "${LocaleKeys.updateInterval.tr()}:"
- `lib/views/market_maker_bot/market_maker_bot_confirmation_form.dart:357` — " (${percentage > 0 ? '+' : ''}${formatAmt(percentage)}%)"
- `lib/views/market_maker_bot/market_maker_bot_confirmation_form.dart:395` — "${formatDexAmt(amount)} "

## Bridge
- `lib/views/bridge/bridge_tab_bar.dart:59` — "${LocaleKeys.inProgress.tr()} ($_inProgressCount)"
- `lib/views/bridge/bridge_tab_bar.dart:65` — "${LocaleKeys.history.tr()} ($_completedCount)"
- `lib/views/bridge/bridge_confirmation.dart:67` — "${LocaleKeys.somethingWrong.tr()} :("
- `lib/views/bridge/bridge_confirmation.dart:201` — "${formatDexAmt(dto.buyAmount)} "

## BLoC error/validator strings (user-facing)
- `lib/bloc/bridge_form/bridge_validator.dart:142` — "Failed to request trade preimage"
- `lib/bloc/bridge_form/bridge_bloc.dart:675` — "Failed to request fees"
- `lib/bloc/taker_form/taker_bloc.dart:611` — "Failed to request fees"
- `lib/bloc/taker_form/taker_validator.dart:320` — "Failed to request trade preimage"
- `lib/bloc/dex_repository.dart:76` — "Something wrong"
- `lib/bloc/dex_repository.dart:93` — "Something wrong"
- `lib/bloc/dex_repository.dart:149` — "Simulated best_orders failure (debug)"
- `lib/bloc/dex_repository.dart:168` — "best_orders returned null response"
- `lib/bloc/faucet_button/faucet_button_bloc.dart:41` — "Faucet request failed: ${response.message}"
- `lib/bloc/faucet_button/faucet_button_bloc.dart:45` — "Network error: ${error.toString()}"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:108` — "Failed to load addresses: $e"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:230` — "Address validation failed: $e"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:259` — "Insufficient funds"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:270` — "Amount must be greater than 0"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:287` — "Invalid amount"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:582` — "Failed to generate preview: $e"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:667` — "Transaction failed: $e"
- `lib/bloc/withdraw_form/withdraw_form_bloc.dart:733` — "Failed to convert address: $e"
- `lib/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart:271` — "Failed to load portfolio profit/loss"
- `lib/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart:358` — "Failed to load portfolio growth"

## UI kit defaults (komodo_ui_kit)
- `packages/komodo_ui_kit/lib/src/buttons/upload_button.dart:7` — "Select a file"
- `packages/komodo_ui_kit/lib/src/buttons/text_dropdown_button.dart:15` — "Select an item"
- `packages/komodo_ui_kit/lib/src/controls/selected_coin_graph_control.dart:110` — "All"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:168` — "1H"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:169` — "${hours}H"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:172` — "1D"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:173` — "${days}D"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:176` — "1W"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:177` — "${weeks}W"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:180` — "1M"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:181` — "${months}M"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:184` — "1Y"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:185` — "${years}Y"
- `packages/komodo_ui_kit/lib/src/inputs/time_period_selector.dart:188` — "Unsupported duration: $duration"

## Legal / disclaimer content
All EULA/Terms/Disclaimer text is hardcoded English in `lib/shared/widgets/disclaimer/constants.dart`. Constants include:
- `disclaimerEulaTitle1`
- `disclaimerTocTitle2` through `disclaimerTocTitle20`
- `disclaimerEulaParagraph1` through `disclaimerEulaParagraph19`
- `disclaimerEulaTitle2` through `disclaimerEulaTitle6`
- `disclaimerEulaParagraph7` through `disclaimerEulaParagraph17`
- `disclaimerEulaLegacyParagraph1`
- `disclaimerTocParagraph2` through `disclaimerTocParagraph19`
