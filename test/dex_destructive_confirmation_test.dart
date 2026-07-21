import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/views/dex/dex_list_filter/mobile/dex_list_header_mobile.dart';
import 'package:web_dex/views/dex/entities_list/orders/order_cancel_button.dart';
import 'package:web_dex/views/dex/entity_details/swap/swap_recover_button.dart';

class _MockTradingEntitiesBloc extends Mock implements TradingEntitiesBloc {}

class _MockMyOrder extends Mock implements MyOrder {}

const _orderUuid = '550e8400-e29b-41d4-a716-446655440001';
const _swapUuid = '550e8400-e29b-41d4-a716-446655440002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('individual cancellation dispatches only after confirmation', (
    tester,
  ) async {
    final bloc = _MockTradingEntitiesBloc();
    final order = _MockMyOrder();
    when(() => order.uuid).thenReturn(_orderUuid);
    when(() => order.base).thenReturn('KMD');
    when(() => order.rel).thenReturn('BTC');
    when(() => bloc.canCancelOrder(_orderUuid)).thenReturn(true);
    when(() => bloc.cancelOrder(_orderUuid)).thenAnswer((_) async => null);

    await tester.pumpWidget(
      _localizedApp(bloc, Scaffold(body: OrderCancelButton(order: order))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.cancelOrder(any()));

    await tester.tap(find.byKey(const Key('dex-order-cancel-confirm')));
    await tester.pumpAndSettle();

    verify(() => bloc.cancelOrder(_orderUuid)).called(1);
  });

  testWidgets('mobile cancel all dispatches only after confirmation', (
    tester,
  ) async {
    final bloc = _MockTradingEntitiesBloc();
    when(() => bloc.cancellableOrderIds).thenReturn(const [_orderUuid]);
    when(() => bloc.cancelExactOrders(const [_orderUuid])).thenAnswer(
      (_) async => const CancelAllOrdersResult(
        attemptedCount: 1,
        cancelledCount: 1,
        failedCount: 0,
        walletChanged: false,
      ),
    );

    await tester.pumpWidget(
      _localizedApp(
        bloc,
        Scaffold(
          body: DexListHeaderMobile(
            listType: DexListType.orders,
            entitiesFilterData: null,
            onFilterPressed: () {},
            onFilterDataChange: (_) {},
            isFilterShown: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel all').last);
    await tester.pumpAndSettle();
    verifyNever(() => bloc.cancelExactOrders(any()));

    await tester.tap(find.byKey(const Key('dex-mobile-cancel-all-confirm')));
    await tester.pumpAndSettle();

    verify(() => bloc.cancelExactOrders(const [_orderUuid])).called(1);
  });

  testWidgets('recovery dispatches only after confirmation', (tester) async {
    final bloc = _MockTradingEntitiesBloc();
    when(() => bloc.outRecoveryStatuses).thenAnswer(
      (_) => const Stream<Map<String, RecoverySubmissionStatus>>.empty(),
    );
    when(
      () => bloc.recoveryStatusFor(_swapUuid),
    ).thenReturn(RecoverySubmissionStatus.idle);
    when(() => bloc.canRecoverSwap(_swapUuid)).thenReturn(true);
    when(
      () => bloc.recoverFundsOfSwap(_swapUuid),
    ).thenAnswer((_) async => null);

    await tester.pumpWidget(
      _localizedApp(
        bloc,
        const Scaffold(body: SwapRecoverButton(uuid: _swapUuid)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unlock Funds'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.recoverFundsOfSwap(any()));

    await tester.tap(find.byKey(const Key('dex-details-recover-confirm')));
    await tester.pump();

    verify(() => bloc.recoverFundsOfSwap(_swapUuid)).called(1);
    await tester.pump(const Duration(seconds: 1));
  });
}

Widget _localizedApp(TradingEntitiesBloc bloc, Widget home) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    fallbackLocale: const Locale('en'),
    useOnlyLangCode: true,
    path: '$assetsPath/translations',
    assetLoader: const _DexTestAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        theme: theme.global.light,
        home: RepositoryProvider<TradingEntitiesBloc>.value(
          value: bloc,
          child: home,
        ),
      ),
    ),
  );
}

class _DexTestAssetLoader extends AssetLoader {
  const _DexTestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return const <String, dynamic>{
      'cancel': 'Cancel',
      'cancelAll': 'Cancel all',
      'cancelOrder': 'Cancel order',
      'confirm': 'Confirm',
      'filters': 'Filters',
      'recover': 'Recover',
      'swapRecoverButtonTitle': 'You need to unlock your funds',
      'swapRecoverButtonText': 'Unlock Funds',
      'swapRecoverButtonErrorMessage': 'Something went wrong',
      'swapRecoverButtonSuccessMessage': 'Recovery succeeded',
    };
  }
}
