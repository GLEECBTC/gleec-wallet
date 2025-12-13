import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/kmd_rewards_bloc.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/bloc_response.dart';
import 'package:web_dex/mm2/mm2_api/rpc/kmd_rewards_info/kmd_reward_item.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/analytics/events/reward_events.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_reward_info_header.dart';
import 'package:web_dex/views/wallet/coin_details/rewards/kmd_reward_list_item.dart';

class KmdRewardsInfo extends StatefulWidget {
  const KmdRewardsInfo({
    Key? key,
    required this.coin,
    required this.onSuccess,
    required this.onBackButtonPressed,
  }) : super(key: key);

  final Coin coin;
  final Function onSuccess;
  final VoidCallback onBackButtonPressed;

  @override
  State<KmdRewardsInfo> createState() => _KmdRewardsInfoState();
}

class _KmdRewardsInfoState extends State<KmdRewardsInfo> {
  String _successMessage = '';
  String _errorMessage = '';
  bool _isClaiming = false;
  List<KmdRewardItem>? _rewards;
  double? _totalReward;
  double? _totalRewardUsd;
  int? _updateTimer;

  bool get _isThereReward => _totalReward != null && _totalReward! > 0;

  Color get _messageColor => _successMessage.isNotEmpty
      ? Colors.green[400]!
      : theme.currentGlobal.colorScheme.error;

  @override
  Widget build(BuildContext context) {
    return PageLayout(
      header: PageHeader(
        title: LocaleKeys.reward.tr(),
        backText: LocaleKeys.backToWallet.tr(),
        onBackButtonPressed: widget.onBackButtonPressed,
      ),
      content: Flexible(
        child: SingleChildScrollView(
          controller: ScrollController(),
          child: _content,
        ),
      ),
    );
  }

  Widget get _content =>
      isDesktop ? _buildDesktop(context) : _buildMobile(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateRewardsInfo();
    });
  }

  Widget _buildContent(BuildContext context) {
    final List<KmdRewardItem>? rewards = _rewards;

    if (rewards == null) return const UiSpinnerList();

    if (rewards.isEmpty) {
      return Text(LocaleKeys.noRewards.tr());
    }

    return _buildRewardList(context);
  }

  Widget _buildControls(BuildContext context) {
    return _isClaiming
        ? const UiSpinner(width: 28, height: 28)
        : UiPrimaryButton(
            key: const Key('reward-claim-button'),
            width: 200,
            text: LocaleKeys.claim.tr(),
            onPressed: _isThereReward
                ? () {
                    _claimRewards(context);
                  }
                : null,
          );
  }

  Widget _buildDesktop(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildTotal(),
                  _buildMessage(),
                  const SizedBox(height: 20),
                  _buildControls(context),
                  const SizedBox(height: 20),
                ],
              ),
              const Spacer(),
              Container(
                width: 350,
                height: 177,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.0),
                  gradient: theme.custom.userRewardBoxColor,
                  boxShadow: [
                    BoxShadow(
                      offset: const Offset(0, 7),
                      blurRadius: 10,
                      color: theme.custom.rewardBoxShadowColor,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocaleKeys.rewardBoxTitle.tr(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                            ),
                          ),
                          Text(
                            LocaleKeys.rewardBoxSubTitle.tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(
                            height: 30.0,
                          ),
                          UiBorderButton(
                            width: 160,
                            height: 38,
                            text: LocaleKeys.rewardBoxReadMore.tr(),
                            onPressed: () {
                              launchURLString(
                                'https://komodoplatform.com/en/docs/komodo/active-user-reward/',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      bottom: 0,
                      right: 0,
                      child: RewardBackground(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Flexible(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildMessage() {
    final String message =
        _successMessage.isEmpty ? _errorMessage : _successMessage;

    return message.isEmpty
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: _messageColor,
              ),
            ),
            child: SelectableText(
              message,
              style: TextStyle(color: _messageColor),
            ),
          );
  }

  Widget _buildMobile(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.0),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 177,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.0),
                  gradient: theme.custom.userRewardBoxColor,
                  boxShadow: [
                    BoxShadow(
                      offset: const Offset(0, 7),
                      blurRadius: 10,
                      color: theme.custom.rewardBoxShadowColor,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocaleKeys.rewardBoxTitle.tr(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                            ),
                          ),
                          Text(
                            LocaleKeys.rewardBoxSubTitle.tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.3),
                            ),
                          ),
                          const SizedBox(height: 24.0),
                          UiBorderButton(
                            width: 160,
                            height: 38,
                            text: LocaleKeys.rewardBoxReadMore.tr(),
                            onPressed: () {
                              launchURLString(
                                'https://komodoplatform.com/en/docs/komodo/active-user-reward/',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      bottom: 0,
                      right: 0,
                      child: RewardBackground(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20.0),
              _buildTotal(),
              _buildMessage(),
              const SizedBox(height: 20),
              _buildControls(context),
            ],
          ),
        ),
        Flexible(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildRewardList(BuildContext context) {
    final scrollController = ScrollController();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        mainAxisSize: MainAxisSize.min,
        children: [
          isDesktop ? _buildRewardListHeader(context) : const SizedBox(),
          const SizedBox(height: 10),
          Flexible(
            child: DexScrollbar(
              scrollController: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: (_rewards ?? []).map(_buildRewardLstItem).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardListHeader(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 3,
          child: Align(
            alignment: const Alignment(-1, 0),
            child: Text(
              LocaleKeys.kmdAmount.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: const Alignment(-1, 0),
            child: Text(
              LocaleKeys.kmdReward.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: const Alignment(-1, 0),
            child: Text(
              LocaleKeys.timeLeft.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
        if (!isMobile)
          Expanded(
            flex: 1,
            child: Align(
              alignment: const Alignment(-1, 0),
              child: Text(
                LocaleKeys.status.tr(),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRewardLstItem(KmdRewardItem reward) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: KmdRewardListItem(reward: reward),
    );
  }

  Widget _buildTotal() {
    final double? totalReward = _totalReward;
    if (totalReward == null) {
      return const SizedBox();
    }

    return KmdRewardInfoHeader(
      totalReward: totalReward,
      totalRewardUsd: _totalRewardUsd,
      isThereReward: _isThereReward,
      coinAbbr: widget.coin.abbr,
    );
  }

  Future<void> _claimRewards(BuildContext context) async {
    setState(() {
      _isClaiming = true;
      _errorMessage = '';
      _successMessage = '';
    });

    context.read<AnalyticsBloc>().logEvent(
          RewardClaimInitiatedEventData(
            asset: widget.coin.abbr,
            expectedRewardAmount: _totalReward ?? 0,
          ),
        );

    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final kmdRewardsBloc = RepositoryProvider.of<KmdRewardsBloc>(context);
    final BlocResponse<String, BaseError> response =
        await kmdRewardsBloc.claim(context);
    final BaseError? error = response.error;
    if (error != null) {
      setState(() {
        _isClaiming = false;
        _errorMessage = error.message;
      });
      context.read<AnalyticsBloc>().logEvent(
            RewardClaimFailureEventData(
              asset: widget.coin.abbr,
              failReason: error.message,
            ),
          );
      return;
    }

    // ignore: use_build_context_synchronously
    context.read<CoinsBloc>().add(CoinsBalancesRefreshed());
    await _updateInfoUntilSuccessOrTimeOut(30000);

    final String reward =
        doubleToString(double.tryParse(response.result!) ?? 0);
    final double? usdPrice =
        coinsRepository.getUsdPriceByAmount(response.result!, 'KMD');
    final String formattedUsdPrice = cutTrailingZeros(formatAmt(usdPrice ?? 0));
    setState(() {
      _isClaiming = false;
    });
    context.read<AnalyticsBloc>().logEvent(
          RewardClaimSuccessEventData(
            asset: widget.coin.abbr,
            rewardAmount: double.tryParse(response.result!) ?? 0,
          ),
        );
    widget.onSuccess(reward, formattedUsdPrice);
  }

  bool _rewardsEquals(
    List<KmdRewardItem> previous,
    List<KmdRewardItem> current,
  ) {
    if (previous.length != current.length) return false;

    for (int i = 0; i < previous.length; i++) {
      if (previous[i].accrueStartAt != current[i].accrueStartAt) return false;
    }

    return true;
  }

  Future<void> _updateInfoUntilSuccessOrTimeOut(int timeOut) async {
    _updateTimer ??= DateTime.now().millisecondsSinceEpoch;
    final List<KmdRewardItem> prevRewards =
        List.from(_rewards ?? <KmdRewardItem>[]);

    await _updateRewardsInfo();

    final bool isTimedOut =
        DateTime.now().millisecondsSinceEpoch - _updateTimer! > timeOut;
    final bool isUpdated = !_rewardsEquals(prevRewards, _rewards ?? []);

    if (isUpdated || isTimedOut) {
      _updateTimer = null;
      return;
    }

    await Future<dynamic>.delayed(const Duration(milliseconds: 1000));
    await _updateInfoUntilSuccessOrTimeOut(timeOut);
  }

  Future<void> _updateRewardsInfo() async {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final kmdRewardsBloc = RepositoryProvider.of<KmdRewardsBloc>(context);
    final double? total = await kmdRewardsBloc.getTotal(context);
    final List<KmdRewardItem> currentRewards = await kmdRewardsBloc.getInfo();
    final double? totalUsd =
        coinsRepository.getUsdPriceByAmount((total ?? 0).toString(), 'KMD');

    if (!mounted) return;
    setState(() {
      _rewards = currentRewards;
      _totalReward = total;
      _totalRewardUsd = totalUsd;
    });
  }
}
