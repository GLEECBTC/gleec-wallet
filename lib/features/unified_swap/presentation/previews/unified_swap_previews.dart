import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_activity_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/swap_entry_view.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

const _previewSource = UnifiedSwapAssetIdentity(
  ticker: 'ETH',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '1',
  kind: UnifiedSwapAssetKind.native,
  decimals: 18,
);

const _previewDestination = UnifiedSwapAssetIdentity(
  ticker: 'USDC',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '42161',
  kind: UnifiedSwapAssetKind.token,
  decimals: 6,
  contractAddress: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
);

final _previewIntent = UnifiedSwapIntent(
  revision: 1,
  source: _previewSource,
  destination: _previewDestination,
  sourceAmount: '1000000000000000000',
  sourceSelection: const UnifiedSwapActiveSourceSelection(),
  recipient: '0x80A10000000000000000000000000000000042F0',
  sourceTokenTrust: UnifiedSwapTokenTrust.trusted,
  destinationTokenTrust: UnifiedSwapTokenTrust.trusted,
);

final _previewCandidate = UnifiedSwapQuoteCandidate(
  candidateId: 'preview-best',
  candidateDigest: 'preview-digest',
  topology: UnifiedSwapTopology.external,
  expectedReceive: '3219420000',
  minimumReceive: '3203320000',
  fees: [
    RouteExecutionFee(
      kind: RouteFeeKind.network,
      asset: _previewSource,
      amount: '2350000000000000',
      included: false,
    ),
  ],
  expiresAt: DateTime.utc(2099),
  rankable: false,
  isExecutable: true,
);

final _previewReady = UnifiedSwapState(
  walletId: 'preview-wallet',
  intent: _previewIntent,
  status: UnifiedSwapQuoteStatus.ready,
  evaluation: UnifiedSwapQuoteEvaluation(
    evaluationId: 'preview-evaluation',
    intentRevision: 1,
    candidates: [_previewCandidate],
  ),
  selectedCandidateId: 'preview-best',
);

@Preview(
  name: 'Entry · 390 dark · ready',
  group: 'Unified Swap',
  size: Size(390, 844),
  brightness: Brightness.dark,
)
Widget unifiedSwapEntryReadyPreview() => _previewApp(
  dark: true,
  child: UnifiedSwapEntryView(
    state: _previewReady,
    onIntentChanged: previewIntentChanged,
    onCandidateSelected: previewCandidateSelected,
    onRevalidate: previewAction,
    onReviewRequested: previewReviewRequested,
    canReview: true,
    reviewUnavailableMessage: '',
    maximumAmountResolver: previewMaximum,
    now: previewNow,
  ),
);

@Preview(
  name: 'Entry · 375 light · checking · 200%',
  group: 'Unified Swap',
  size: Size(375, 812),
  brightness: Brightness.light,
  textScaleFactor: 2,
)
Widget unifiedSwapEntryCheckingPreview() => _previewApp(
  dark: false,
  textScale: 2,
  child: UnifiedSwapEntryView(
    state: UnifiedSwapState(
      walletId: 'preview-wallet',
      intent: _previewIntent,
      status: UnifiedSwapQuoteStatus.loading,
    ),
    onIntentChanged: previewIntentChanged,
    onCandidateSelected: previewCandidateSelected,
    onRevalidate: previewAction,
    onReviewRequested: previewReviewRequested,
    canReview: false,
    reviewUnavailableMessage: 'Review is not available while checking.',
    maximumAmountResolver: previewMaximum,
    now: previewNow,
  ),
);

@Preview(
  name: 'Entry · 390 light · timeout',
  group: 'Unified Swap',
  size: Size(390, 844),
  brightness: Brightness.light,
)
Widget unifiedSwapEntryTimeoutPreview() => _previewApp(
  dark: false,
  child: UnifiedSwapEntryView(
    state: UnifiedSwapState(
      walletId: 'preview-wallet',
      intent: _previewIntent,
      status: UnifiedSwapQuoteStatus.unavailable,
      failure: UnifiedSwapQuoteFailure.networkUnavailable,
    ),
    onIntentChanged: previewIntentChanged,
    onCandidateSelected: previewCandidateSelected,
    onRevalidate: previewAction,
    onReviewRequested: previewReviewRequested,
    canReview: false,
    reviewUnavailableMessage: '',
    maximumAmountResolver: previewMaximum,
    now: previewNow,
  ),
);

@Preview(
  name: 'Recovery · ambiguous broadcast · dark',
  group: 'Unified Swap',
  size: Size(390, 844),
  brightness: Brightness.dark,
)
Widget unifiedSwapRecoveryHierarchyPreview() => _previewApp(
  dark: true,
  child: ListView(
    padding: const EdgeInsets.all(24),
    children: const [
      UnifiedSwapPageTitle(title: 'Recovery'),
      SizedBox(height: 12),
      UnifiedSwapStatusHero(
        title: 'We’re checking whether the transaction was sent',
        icon: Icons.manage_search_rounded,
        tone: UnifiedSwapNoticeTone.brand,
      ),
      UnifiedSwapQuestion(
        first: true,
        question: 'What happened?',
        answer: 'We’re checking whether the transaction was sent',
        details:
            'The signing step completed, but the network result is unclear.',
      ),
      UnifiedSwapQuestion(
        question: 'Where are the funds?',
        answer: 'Last confirmed location · current location unknown',
        details:
            'Last confirmed location: 1 ETH at 0x5520…7B91 on Ethereum. '
            'Current location is not yet verified.',
      ),
      UnifiedSwapQuestion(
        question: 'What can I do now?',
        answer: 'Only verified, currently available actions are shown',
        details:
            'Fresh consent is always required before starting another swap.',
      ),
    ],
  ),
);

Widget _previewApp({
  required bool dark,
  required Widget child,
  double textScale = 1,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: newThemeLight,
    darkTheme: newThemeDark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  );
}

Future<bool> previewIntentChanged(UnifiedSwapIntent _) async => true;
void previewCandidateSelected(String _) {}
void previewReviewRequested(UnifiedSwapQuoteCandidate _) {}
void previewAction() {}
Future<String?> previewMaximum(UnifiedSwapIntent _) async =>
    '2470000000000000000';
DateTime previewNow() => DateTime.utc(2026, 7, 19);
