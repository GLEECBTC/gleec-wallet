import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/nfts/common/widgets/nft_no_login.dart';

/// Shown when the NFT gallery has no chain to offer at all.
///
/// Since an un-enabled chain now earns its own tab, this is reachable only when
/// the whole catalogue is missing or geo-blocked - never as a way to tell the
/// user to go and enable something.
class NftNoChainsEnabled extends StatelessWidget {
  const NftNoChainsEnabled({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: NftNoLogin(text: LocaleKeys.nftNoNetworksAvailable.tr()),
        ),
      ],
    );
  }
}
