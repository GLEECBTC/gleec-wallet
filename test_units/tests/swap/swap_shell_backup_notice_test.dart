import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/backup_seed_notification.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser _user({required bool hasBackup}) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'notice-wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'notice-wallet-pubkey-hash',
  ),
  isBip39Seed: true,
  metadata: {
    'type': 'hdwallet',
    'has_backup': hasBackup,
    'wallet_provenance': 'generated',
  },
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool hasBackup,
}) async {
  final auth = _AuthBloc(AuthBlocState.loggedIn(_user(hasBackup: hasBackup)));
  addTearDown(auth.close);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: auth,
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

/// The notice's title, the one line it always shows.
Finder _notice() => find.descendant(
  of: find.byType(BackupSeedNotification),
  matching: find.byType(Text),
);

void main() {
  group('Swap surface backup notice', () {
    for (final destination in SwapDestination.values) {
      testWidgets('shows once on ${destination.name} for a wallet not yet '
          'backed up', (tester) async {
        await _pump(
          tester,
          SwapShell(
            initialDestination: destination,
            destinationBuilder: (d) => Text('body:${d.name}'),
          ),
          hasBackup: false,
        );

        expect(find.text('body:${destination.name}'), findsOneWidget);
        expect(find.byType(BackupSeedNotification), findsOneWidget);
        expect(_notice(), findsWidgets);
      });
    }

    testWidgets('stays put while switching destinations', (tester) async {
      await _pump(
        tester,
        SwapShell(destinationBuilder: (d) => Text('body:${d.name}')),
        hasBackup: false,
      );
      final before = tester.getRect(find.byType(BackupSeedNotification));

      await tester.tap(find.byKey(const Key('swap-destination-activity')));
      await tester.pumpAndSettle();

      expect(find.text('body:activity'), findsOneWidget);
      expect(tester.getRect(find.byType(BackupSeedNotification)), before);
    });

    testWidgets('says nothing once the seed is backed up', (tester) async {
      await _pump(
        tester,
        SwapShell(destinationBuilder: (d) => Text('body:${d.name}')),
        hasBackup: true,
      );

      expect(_notice(), findsNothing);
    });

    testWidgets('a page inside the surface can leave its own notice out', (
      tester,
    ) async {
      // The trading page under Advanced does this, so the notice the
      // surface shows is not repeated below it.
      await _pump(
        tester,
        const PageLayout(showBackupNotice: false, content: Text('page')),
        hasBackup: false,
      );
      expect(find.byType(BackupSeedNotification), findsNothing);

      await _pump(
        tester,
        const PageLayout(content: Text('page')),
        hasBackup: false,
      );
      expect(find.byType(BackupSeedNotification), findsOneWidget);
    });
  });
}
