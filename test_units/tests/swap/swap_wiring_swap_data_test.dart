// test_units is analysed as app code, where the plugins' test mocks warn.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/views/settings/widgets/general_settings/show_swap_data.dart';

import 'swap_test_fixtures.dart';
import 'swap_wiring_fakes.dart';

/// The support export carries routed swaps next to atomic ones.
void main() {
  group('Swap data export', () {
    late FakeMm2Api mm2;
    late FakeRoutedSwaps routed;
    late _SavePicker picker;
    late _SavedFile saved;
    FilePicker? previousPicker;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      try {
        previousPicker = FilePicker.platform;
      } on Error {
        previousPicker = null;
      }
    });

    tearDownAll(() {
      if (previousPicker case final picker?) FilePicker.platform = picker;
    });

    setUp(() {
      mm2 = FakeMm2Api(rawSwapData: jsonEncode(_atomic));
      routed = FakeRoutedSwaps(
        pages: [
          _page([_finished, _failed, _pending]),
        ],
      );
      saved = _SavedFile('/exports/swap_data.json');
      picker = _SavePicker(saved.path);
      FilePicker.platform = picker;
      IOOverrides.global = saved;
    });

    tearDown(() {
      IOOverrides.global = null;
      picker.path = null;
      Localization.load(const Locale('en'));
    });

    Future<void> pumpData(WidgetTester tester) => pumpLocalized(
      tester,
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<Mm2Api>.value(value: mm2),
          RepositoryProvider<KomodoDefiSdk>.value(
            value: FakeSdk(routedSwaps: routed),
          ),
        ],
        child: const Scaffold(
          body: SingleChildScrollView(child: ShowSwapData()),
        ),
      ),
      size: const Size(1024, 900),
    );

    Future<Map<String, dynamic>> export(WidgetTester tester) async {
      await tester.tap(find.text('Export swap data'));
      await tester.pump(Duration.zero);
      return jsonDecode(saved.written!) as Map<String, dynamic>;
    }

    testWidgets('exports atomic and routed swaps together in one file', (
      tester,
    ) async {
      await pumpData(tester);

      final bundle = await export(tester);

      expect(bundle.keys, unorderedEquals(['exported_at', 'atomic', 'routed']));
      // The atomic half is the raw my_recent_swaps answer, as JSON.
      expect(bundle['atomic'], _atomic);
      expect(DateTime.parse(bundle['exported_at'] as String).isUtc, isTrue);
      expect((bundle['routed'] as List).map((swap) => (swap as Map)['uuid']), [
        'routed-finished',
        'routed-failed',
        'routed-pending',
      ]);
      expect(
        picker.suggestedName,
        matches(RegExp(r'^swap_data_\d{4}-\d\d-\d\dT[\d:.]+Z\.json$')),
      );
      // Done: the button is back.
      expect(find.byType(UiSpinner), findsNothing);
    });

    testWidgets('describes each routed swap with what support needs', (
      tester,
    ) async {
      await pumpData(tester);

      final swaps = (await export(tester))['routed'] as List;

      expect(swaps[0], {
        ..._blank,
        'uuid': 'routed-finished',
        'phase': 'finished',
        'raw_state': 'Finished',
        'created_at': '2026-09-24T12:00:00.000Z',
        'updated_at': '2026-09-24T12:04:00.000Z',
        'finished_at': '2026-09-24T12:05:00.000Z',
        'requested_from': 'ETH',
        'requested_to': 'USDC-ERC20',
        'requested_amount': '1.5',
        'min_to_amount_accepted': '4400',
        'outcome': 'partial',
        'partial_reason': 'belowMinimum',
        'received_amount': '4390.25',
        'received_token': 'USDC-ERC20',
        'source_tx_hash': '0xsource',
        'destination_tx_hash': '0xdestination',
        'explorer_url': 'https://scan.li.fi/tx/0xsource',
        'gas_spent': [
          {'coin': 'ETH', 'amount': '0.0021', 'tx_hash': '0xsource'},
        ],
      });
      expect(swaps[1], {
        ..._blank,
        'uuid': 'routed-failed',
        'phase': 'failed',
        'raw_state': 'Failed',
        'stage': 'refundPending',
        'failure': 'bridgeFailed',
        'error_type': 'BridgeFailed',
        'failure_message': 'The bridge did not deliver',
        'funds_movement': 'sent',
        'provider_request_id': 'lifi-req-7',
        'approval_tx_hashes': ['0xreset', '0xapprove'],
        'gas_spent': [
          {'coin': 'ETH', 'amount': '0.0003', 'tx_hash': '0xreset'},
          {'coin': 'ETH', 'amount': '0.0004', 'tx_hash': null},
        ],
      });
      // A swap that has recorded nothing yet still appears, with empty fields.
      expect(swaps[2], {
        ..._blank,
        'uuid': 'routed-pending',
        'phase': 'preparing',
      });
    });

    testWidgets('reads routed history 50 at a time, at most four pages', (
      tester,
    ) async {
      routed.pages = [
        for (var page = 1; page <= 5; page++)
          _page([_numbered(page)], page: page, of: 5),
      ];
      await pumpData(tester);

      final swaps = (await export(tester))['routed'] as List;

      expect(routed.historyCalls, [
        for (var page = 1; page <= 4; page++) (page: page, limit: 50),
      ]);
      expect(swaps.map((swap) => (swap as Map)['uuid']), [
        'page-1',
        'page-2',
        'page-3',
        'page-4',
      ]);
    });

    testWidgets('stops reading at the last page', (tester) async {
      routed.pages = [
        _page([_numbered(1)], page: 1, of: 2),
        _page([_numbered(2)], page: 2, of: 2),
      ];
      await pumpData(tester);

      final swaps = (await export(tester))['routed'] as List;

      expect(routed.historyCalls, [(page: 1, limit: 50), (page: 2, limit: 50)]);
      expect(swaps, hasLength(2));
    });

    testWidgets('says why routed swaps are missing rather than listing none', (
      tester,
    ) async {
      routed.error = StateError('routed history down');
      await pumpData(tester);

      final bundle = await export(tester);

      // An empty list would read as "this user has no routed swaps".
      expect(bundle['routed'], {
        'unavailable': 'Bad state: routed history down',
      });
      expect(bundle['atomic'], _atomic);
      expect(find.byType(UiSpinner), findsNothing);
    });

    testWidgets(
      'says why atomic swaps are missing, and keeps the routed ones',
      (tester) async {
        mm2.rawSwapError = StateError('engine down');
        await pumpData(tester);

        final bundle = await export(tester);

        expect(bundle['atomic'], {'unavailable': 'Bad state: engine down'});
        expect(bundle['routed'], hasLength(greaterThan(0)));
        expect(find.byType(UiSpinner), findsNothing);
      },
    );

    testWidgets('Show swap data lists the atomic swaps, and hides them again', (
      tester,
    ) async {
      await pumpData(tester);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Show swap data'));
      await tester.pump(Duration.zero);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        jsonDecode(field.controller!.text),
        (_atomic['result'] as Map)['swaps'],
      );

      await tester.tap(find.text('Show swap data'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
    });
  });
}

const _atomic = <String, dynamic>{
  'result': {
    'swaps': [
      {
        'uuid': 'atomic-1',
        'my_info': {'my_coin': 'DOC', 'other_coin': 'MARTY'},
      },
    ],
    'total': 1,
  },
};

/// Every exported field, empty.
const _blank = <String, dynamic>{
  'uuid': null,
  'phase': null,
  'raw_state': null,
  'stage': null,
  'created_at': null,
  'updated_at': null,
  'finished_at': null,
  'requested_from': null,
  'requested_to': null,
  'requested_amount': null,
  'min_to_amount_accepted': null,
  'outcome': null,
  'partial_reason': null,
  'received_amount': null,
  'received_token': null,
  'failure': null,
  'error_type': null,
  'failure_message': null,
  'funds_movement': null,
  'provider_request_id': null,
  'approval_tx_hashes': <String>[],
  'source_tx_hash': null,
  'destination_tx_hash': null,
  'explorer_url': null,
  'gas_spent': <Object>[],
};

RoutedSwapHistoryPage _page(
  List<RoutedSwapProgress> entries, {
  int page = 1,
  int of = 1,
}) => RoutedSwapHistoryPage(
  entries: entries,
  total: entries.length,
  pageNumber: page,
  totalPages: of,
);

RoutedSwapProgress _numbered(int page) => RoutedSwapProgress(
  uuid: 'page-$page',
  phase: RoutedSwapPhase.finished,
  canCancel: false,
);

final _finished = RoutedSwapProgress(
  uuid: 'routed-finished',
  phase: RoutedSwapPhase.finished,
  canCancel: false,
  rawState: 'Finished',
  createdAt: DateTime.utc(2026, 9, 24, 12),
  updatedAt: DateTime.utc(2026, 9, 24, 12, 4),
  finishedAt: DateTime.utc(2026, 9, 24, 12, 5),
  requested: RoutedSwapRequest(
    fromTicker: 'ETH',
    toTicker: 'USDC-ERC20',
    amount: d('1.5'),
  ),
  minToAmountAccepted: d('4400'),
  receipt: RoutedSwapReceipt(
    outcome: rpc.RoutedSwapOutcome.partial,
    partialReason: rpc.RoutedSwapPartialReason.belowMinimum,
    amount: d('4390.25'),
    assetId: usdc,
  ),
  sourceTxHash: '0xsource',
  destinationTxHash: '0xdestination',
  explorerUrl: 'https://scan.li.fi/tx/0xsource',
  gasSpent: [
    RoutedSwapGasPaid(ticker: 'ETH', amount: d('0.0021'), txHash: '0xsource'),
  ],
);

final _failed = RoutedSwapProgress(
  uuid: 'routed-failed',
  phase: RoutedSwapPhase.failed,
  canCancel: false,
  rawState: 'Failed',
  bridgeStage: rpc.RoutedSwapBridgeStage.refundPending,
  failure: const RoutedSwapFailure(
    kind: RoutedSwapFailureKind.bridgeFailed,
    errorType: 'BridgeFailed',
    message: 'The bridge did not deliver',
    fundsMovement: RoutedSwapFundsMovement.sent,
    retryPolicy: RoutedSwapRetryPolicy.contactSupport,
    providerRequestId: 'lifi-req-7',
  ),
  approvalTxHashes: const ['0xreset', '0xapprove'],
  gasSpent: [
    RoutedSwapGasPaid(ticker: 'ETH', amount: d('0.0003'), txHash: '0xreset'),
    RoutedSwapGasPaid(ticker: 'ETH', amount: d('0.0004')),
  ],
);

const _pending = RoutedSwapProgress(
  uuid: 'routed-pending',
  phase: RoutedSwapPhase.preparing,
  canCancel: true,
);

/// The desktop save dialog: suggests [path] for whatever is being saved.
class _SavePicker extends FilePicker {
  _SavePicker(this.path);

  /// Where the "user" saves; null once the test is over.
  String? path;
  String? suggestedName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    final target = path;
    if (target == null) throw UnimplementedError('saveFile');
    suggestedName = fileName;
    return target;
  }
}

/// Keeps the file saved at [path] in memory; every other path is real.
final class _SavedFile extends IOOverrides {
  _SavedFile(this.path);

  final String path;
  String? written;

  @override
  File createFile(String path) =>
      path == this.path ? _MemoryFile(path, this) : super.createFile(path);
}

class _MemoryFile implements File {
  _MemoryFile(this.path, this._owner);

  @override
  final String path;
  final _SavedFile _owner;

  @override
  void createSync({bool recursive = false, bool exclusive = false}) {}

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    _owner.written = contents;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
