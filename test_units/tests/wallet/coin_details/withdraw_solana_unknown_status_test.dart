import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/wallet.dart' show WalletType;
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

const _signature =
    '5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW';

Asset _solana({bool withExplorer = true}) => Asset(
  id: AssetId(
    id: 'SOL',
    name: 'Solana',
    symbol: AssetSymbol(assetConfigId: 'SOL'),
    chainId: AssetChainId(chainId: 0),
    derivationPath: null,
    subClass: CoinSubClass.solana,
  ),
  protocol: SolanaProtocol.fromJson({
    'is_testnet': false,
    'nodes': [
      {'url': 'https://api.mainnet-beta.solana.com'},
    ],
    if (withExplorer) ...{
      'explorer_url': 'https://explorer.solana.com/',
      'explorer_tx_url': 'tx/{HASH}',
    },
  }),
  isWalletOnly: false,
  signMessagePrefix: null,
);

WithdrawFormState _state({String? unknownSignature, Asset? asset}) =>
    WithdrawFormState(
      asset: asset ?? _solana(),
      step: WithdrawFormStep.failed,
      walletType: WalletType.hdwallet,
      recipientAddress: 'recipient',
      amount: '1',
      isGaslessFeatureConfigured: false,
      solanaSubmissionUnknownTxHash: unknownSignature,
      transactionError: TextError(error: 'The network did not answer'),
    );

class _WithdrawFormBloc extends Cubit<WithdrawFormState>
    implements WithdrawFormBloc {
  _WithdrawFormBloc(super.initialState);

  final events = <WithdrawFormEvent>[];

  @override
  void add(WithdrawFormEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens nothing; remembers every URL it was asked to.
class _UrlLauncher extends UrlLauncherPlatform {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late List<String> copied;
  late _UrlLauncher launcher;

  setUp(() {
    copied = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final previous = UrlLauncherPlatform.instance;
    launcher = _UrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
  });

  Future<_WithdrawFormBloc> pump(
    WidgetTester tester,
    WithdrawFormState state,
  ) async {
    final bloc = _WithdrawFormBloc(state);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BlocProvider<WithdrawFormBloc>.value(
              value: bloc,
              child: const WithdrawFormFailedSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return bloc;
  }

  const signatureField = Key('withdraw-solana-unknown-signature');
  const explorerButton = Key('withdraw-solana-unknown-explorer');

  group('Solana transfer with an unknown status', () {
    testWidgets('the signature it asks the user to check can be copied', (
      tester,
    ) async {
      await pump(tester, _state(unknownSignature: _signature));

      await tester.tap(find.byKey(signatureField));
      await tester.pump();
      expect(copied, [_signature]);
      // Let the copy confirmation run out before the test ends.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('the explorer opens on that signature', (tester) async {
      await pump(tester, _state(unknownSignature: _signature));

      await tester.tap(find.byKey(explorerButton));
      await tester.pump();
      expect(launcher.launched, ['https://explorer.solana.com/tx/$_signature']);
    });

    testWidgets('an asset without an explorer still offers the copy', (
      tester,
    ) async {
      await pump(
        tester,
        _state(
          unknownSignature: _signature,
          asset: _solana(withExplorer: false),
        ),
      );
      expect(find.byKey(signatureField), findsOneWidget);
      expect(find.byKey(explorerButton), findsNothing);
    });

    testWidgets('neither going back nor retrying is offered', (tester) async {
      final bloc = await pump(tester, _state(unknownSignature: _signature));

      final back = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final retry = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(back.onPressed, isNull);
      expect(retry.onPressed, isNull);
      expect(bloc.events, isEmpty);
    });

    testWidgets('an ordinary failure shows no signature controls', (
      tester,
    ) async {
      await pump(tester, _state());
      expect(find.byKey(signatureField), findsNothing);
      expect(find.byKey(explorerButton), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });
  });
}
