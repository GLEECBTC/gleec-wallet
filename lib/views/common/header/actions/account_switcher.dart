import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_wrapper.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';

const double minWidth = 100;
const double maxWidth = 350;

class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const ConnectWalletWrapper(
      buttonSize: Size(160, 30),
      withIcon: true,
      eventType: WalletsManagerEventType.header,
      child: _AccountSwitcher(),
    );
  }
}

class _AccountSwitcher extends StatelessWidget {
  const _AccountSwitcher();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BlocBuilder<AuthBloc, AuthBlocState>(
            builder: (context, state) {
              return Container(
                constraints: const BoxConstraints(maxWidth: maxWidth),
                child: Text(
                  state.currentUser?.walletId.name ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Theme.of(context).textTheme.labelLarge?.color,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          const _AccountIcon(),
        ],
      ),
    );
  }
}

class _AccountIcon extends StatelessWidget {
  const _AccountIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SvgPicture.asset(
          '$assetsPath/ui_icons/account.svg',
          colorFilter: ColorFilter.mode(
            theme.custom.headerFloatBoxColor,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
