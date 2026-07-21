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
    when(() => order.uuid).thenReturn('order-1');
    when(() => bloc.cancelOrder('order-1')).thenAnswer((_) async => null);

    await tester.pumpWidget(
      _localizedApp(bloc, Scaffold(body: OrderCancelButton(order: order))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.cancelOrder(any()));

    await tester.tap(find.byKey(const Key('dex-order-cancel-confirm')));
    await tester.pumpAndSettle();

    verify(() => bloc.cancelOrder('order-1')).called(1);
  });

  testWidgets('mobile cancel all dispatches only after confirmation', (
    tester,
  ) async {
    final bloc = _MockTradingEntitiesBloc();
    when(bloc.cancelAllOrders).thenAnswer((_) async {});

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
    verifyNever(bloc.cancelAllOrders);

    await tester.tap(find.byKey(const Key('dex-mobile-cancel-all-confirm')));
    await tester.pumpAndSettle();

    verify(bloc.cancelAllOrders).called(1);
  });

  testWidgets('recovery dispatches only after confirmation', (tester) async {
    final bloc = _MockTradingEntitiesBloc();
    when(() => bloc.recoverFundsOfSwap('swap-1')).thenAnswer((_) async => null);

    await tester.pumpWidget(
      _localizedApp(
        bloc,
        const Scaffold(body: SwapRecoverButton(uuid: 'swap-1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unlock Funds'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.recoverFundsOfSwap(any()));

    await tester.tap(find.byKey(const Key('dex-details-recover-confirm')));
    await tester.pump();

    verify(() => bloc.recoverFundsOfSwap('swap-1')).called(1);
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
