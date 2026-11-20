import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

void main() {
  group('WalletUnlockCoordinator', () {
    late Duration now;
    late WalletOperationGate gate;
    late WalletUnlockCoordinator coordinator;

    setUp(() {
      now = Duration.zero;
      gate = WalletOperationGate();
      coordinator = WalletUnlockCoordinator(
        monotonicNow: () => now,
        operationGate: gate,
      );
    });

    tearDown(() async => coordinator.dispose());

    void attach({bool authenticated = true, bool protected = true}) =>
        coordinator.attachWallet(
          'entry-a',
          requiresAuthentication: protected,
          authenticated: authenticated,
        );

    test('bootstrap installs a signed-out operation authority', () {
      expect(gate.isInstalled, isTrue);
      expect(gate.allowsOperations, isFalse);
      coordinator.attachWallet(null, requiresAuthentication: false);
      expect(gate.capture, throwsA(isA<WalletOperationDenied>()));
    });

    group('verified system prompt foreground handoff', () {
      test(
        'immediate lock accepts resumed before successful native reply',
        () async {
          attach();
          coordinator.setBackgroundGrace(Duration.zero);
          final reply = Completer<String>();
          final pending = coordinator.runSystemPrompt(
            () => reply.future,
            waitForForeground: true,
          );
          coordinator.background();
          coordinator.resume();
          expect(coordinator.state.isLocked, isTrue);
          reply.complete('verified-result');
          expect(await pending, 'verified-result');
          expect(coordinator.state.isLocked, isFalse);
          expect(gate.allowsOperations, isTrue);
        },
      );
      test(
        'missing native resume expires and clears prompt ownership',
        () async {
          attach();
          coordinator.setBackgroundGrace(Duration.zero);
          final reply = Completer<String>();
          final pending = coordinator.runSystemPrompt(
            () => reply.future,
            waitForForeground: true,
          );
          final rejected = expectLater(
            pending,
            throwsA(
              isA<WalletAccessException>().having(
                (error) => error.failure,
                'failure',
                WalletAccessFailure.staleOperation,
              ),
            ),
          );
          coordinator.background();
          reply.complete('verified-result');
          await Future<void>.delayed(Duration.zero);
          expect(coordinator.hasSystemPrompt, isTrue);
          await rejected;
          now += const Duration(seconds: 6);
          expect(coordinator.hasSystemPrompt, isFalse);
          coordinator.resume();
          expect(coordinator.state.isLocked, isTrue);
          expect(gate.allowsOperations, isFalse);
        },
      );

      test(
        'failed native operation cannot establish a return handoff',
        () async {
          attach();
          coordinator.setBackgroundGrace(Duration.zero);
          final reply = Completer<String>();
          final pending = coordinator.runSystemPrompt(
            () => reply.future,
            waitForForeground: true,
          );
          final rejected = expectLater(
            pending,
            throwsA(
              isA<WalletAccessException>().having(
                (error) => error.failure,
                'failure',
                WalletAccessFailure.canceled,
              ),
            ),
          );
          coordinator.background();
          reply.completeError(
            const WalletAccessException(WalletAccessFailure.canceled),
          );
          await rejected;
          expect(coordinator.hasSystemPrompt, isFalse);
          coordinator.resume();
          expect(coordinator.state.isLocked, isTrue);
          expect(gate.allowsOperations, isFalse);
        },
      );

      for (final immediate in [false, true]) {
        test('waits for native resume once, immediate=$immediate', () async {
          attach();
          if (immediate) coordinator.setBackgroundGrace(Duration.zero);
          final reply = Completer<String>();
          var completed = false;
          final pending = coordinator
              .runSystemPrompt(() => reply.future, waitForForeground: true)
              .then((value) {
                completed = true;
                return value;
              });
          coordinator.inactive();
          coordinator.background();
          reply.complete('verified-result');
          await Future<void>.delayed(Duration.zero);
          expect(completed, isFalse);
          expect(gate.allowsOperations, isFalse);
          expect(coordinator.hasSystemPrompt, isTrue);
          coordinator.resume();
          expect(await pending, 'verified-result');
          expect(coordinator.state.isLocked, isFalse);
          expect(coordinator.hasSystemPrompt, isFalse);
          coordinator.background();
          now += const Duration(seconds: 31);
          coordinator.resume();
          expect(coordinator.state.isLocked, isTrue);
        });
      }
      for (final interruption in [
        'lock',
        'device',
        'switch',
        'inactive',
        'background',
        'late resume',
      ]) {
        test(
          '$interruption revokes completed prompt before dispatch',
          () async {
            attach();
            final reply = Completer<String>();
            final pending = coordinator.runSystemPrompt(
              () => reply.future,
              waitForForeground: true,
            );
            final rejected = expectLater(
              pending,
              throwsA(
                isA<WalletAccessException>().having(
                  (error) => error.failure,
                  'failure',
                  WalletAccessFailure.staleOperation,
                ),
              ),
            );
            coordinator.inactive();
            coordinator.background();
            reply.complete('verified-result');
            await Future<void>.delayed(Duration.zero);
            switch (interruption) {
              case 'lock':
                coordinator.lock();
              case 'device':
                coordinator.deviceLocked();
              case 'switch':
                coordinator.attachWallet('other', requiresAuthentication: true);
              case 'inactive':
                coordinator.inactive();
              case 'background':
                coordinator.background();
              case 'late resume':
                now += const Duration(seconds: 6);
                coordinator.resume();
            }
            await rejected;
            expect(coordinator.hasSystemPrompt, isFalse);
          },
        );
      }
    });

    group('non-authentication system dialog return', () {
      for (final immediate in [false, true]) {
        for (final resumeFirst in [false, true]) {
          test(
            'selection never unlocks, immediate=$immediate resumeFirst=$resumeFirst',
            () async {
              attach();
              if (immediate) coordinator.setBackgroundGrace(Duration.zero);
              final reply = Completer<String?>();
              final pending = coordinator.runSystemDialogAwaitingForeground(
                () => reply.future,
              );
              coordinator.background();
              now += const Duration(seconds: 31);
              if (resumeFirst) coordinator.resume();
              expect(coordinator.beginUnlock(automatic: true), isNull);
              reply.complete('synthetic-destination-token');
              if (!resumeFirst) {
                await Future<void>.delayed(Duration.zero);
                expect(gate.allowsOperations, isFalse);
                coordinator.resume();
              }
              expect(await pending, 'synthetic-destination-token');
              expect(coordinator.state.isLocked, isTrue);
              expect(gate.allowsOperations, isFalse);
              expect(coordinator.beginUnlock(automatic: true), isNull);
              expect(coordinator.beginUnlock(), isNotNull);
            },
          );
        }
      }
      test('missing picker resume expires without unlocking', () async {
        attach();
        coordinator.setBackgroundGrace(Duration.zero);
        final reply = Completer<String?>();
        final pending = coordinator.runSystemDialogAwaitingForeground(
          () => reply.future,
        );
        final rejected = expectLater(
          pending,
          throwsA(
            isA<WalletAccessException>().having(
              (error) => error.failure,
              'failure',
              WalletAccessFailure.staleOperation,
            ),
          ),
        );
        coordinator.background();
        reply.complete('synthetic-destination-token');
        await rejected;
        expect(coordinator.hasSystemPrompt, isFalse);
        expect(coordinator.state.isLocked, isTrue);
        coordinator.resume();
        expect(coordinator.state.isLocked, isTrue);
      });
    });

    test('cold protected attachment requires fresh unlock', () {
      attach(authenticated: false);

      expect(coordinator.state.isLocked, isTrue);
      expect(coordinator.state.coversContent, isTrue);
      expect(gate.allowsOperations, isFalse);
      final attempt = coordinator.beginUnlock(automatic: true)!;
      expect(coordinator.beginUnlock(), isNull);
      expect(coordinator.completeUnlock(attempt), isTrue);
      expect(coordinator.completeUnlock(attempt), isFalse);
      expect(gate.allowsOperations, isTrue);
    });

    test(
      'state listener can begin automatic unlock without reentrancy',
      () async {
        UnlockAttempt? attempt;
        final subscription = coordinator.changes.listen((state) {
          if (state.canStartUnlock) {
            attempt = coordinator.beginUnlock(automatic: true);
          }
        });
        attach(authenticated: false);
        await Future<void>.delayed(Duration.zero);
        expect(attempt, isNotNull);
        expect(coordinator.state.unlockInProgress, isTrue);
        await subscription.cancel();
      },
    );

    test('canceled automatic challenge never loops', () {
      attach(authenticated: false);
      final attempt = coordinator.beginUnlock(automatic: true)!;
      coordinator.cancelUnlock(attempt);

      expect(coordinator.beginUnlock(automatic: true), isNull);
      coordinator.inactive();
      coordinator.background();
      now += const Duration(seconds: 60);
      coordinator.resume();
      expect(coordinator.beginUnlock(automatic: true), isNull);
      expect(coordinator.beginUnlock(), isNotNull);
      expect(coordinator.state.isLocked, isTrue);
    });

    test('29 second return preserves session but revokes queued action', () {
      attach();
      final pendingSend = gate.capture(expectedWalletEntryId: 'entry-a');
      coordinator.inactive();
      coordinator.background();
      expect(coordinator.state.coversContent, isTrue);
      expect(gate.allowsOperations, isFalse);

      now += const Duration(seconds: 29);
      coordinator.resume();

      expect(coordinator.state.coversContent, isFalse);
      expect(gate.allowsOperations, isTrue);
      expect(pendingSend.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
      gate.capture(expectedWalletEntryId: 'entry-a').ensureCurrent();
    });

    test('31 second return expires even without a background timer', () {
      attach();
      coordinator.background();
      now += const Duration(seconds: 31);
      coordinator.resume();

      expect(coordinator.state.isLocked, isTrue);
      expect(gate.allowsOperations, isFalse);
      expect(coordinator.beginUnlock(automatic: true), isNotNull);
    });

    test('repeated background events never extend the grace', () {
      attach();
      coordinator.background();
      now += const Duration(seconds: 25);
      coordinator.background();
      now += const Duration(seconds: 6);
      coordinator.resume();
      expect(coordinator.state.isLocked, isTrue);
    });

    test('same SDK session restoration cannot clear app lock', () {
      final session = Object();
      coordinator.attachWallet(
        'entry-a',
        requiresAuthentication: true,
        authenticated: true,
        sessionIdentity: session,
      );
      coordinator.lock();
      coordinator.attachWallet(
        'entry-a',
        requiresAuthentication: true,
        authenticated: true,
        sessionIdentity: session,
      );
      expect(coordinator.state.isLocked, isTrue);
      expect(gate.allowsOperations, isFalse);
      expect(coordinator.beginUnlock(automatic: true), isNull);
    });

    group('inactive-only lifecycle', () {
      for (final seconds in [0, 29, 31]) {
        test('unowned return after $seconds seconds observes grace', () {
          attach();
          if (seconds == 0) coordinator.setBackgroundGrace(Duration.zero);
          final queued = gate.capture();
          final authorization = coordinator.authorizationGeneration;
          coordinator.inactive();
          expect(
            coordinator.authorizationGeneration,
            greaterThan(authorization),
          );
          expect(coordinator.state.coversContent, isTrue);
          expect(gate.allowsOperations, isFalse);
          expect(coordinator.state.isLocked, seconds == 0);
          now += Duration(seconds: seconds);
          coordinator.resume();
          expect(coordinator.state.isLocked, seconds != 29);
          expect(gate.allowsOperations, seconds == 29);
          expect(queued.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
        });
      }

      test(
        'repeated inactivity and later background retain first deadline',
        () {
          attach();
          coordinator.inactive();
          now += const Duration(seconds: 25);
          coordinator.inactive();
          coordinator.background();
          now += const Duration(seconds: 6);
          coordinator.resume();
          expect(coordinator.state.isLocked, isTrue);
        },
      );

      for (final immediate in [false, true]) {
        test('live owned prompt remains valid, immediate=$immediate', () async {
          attach();
          if (immediate) coordinator.setBackgroundGrace(Duration.zero);
          final reply = Completer<void>();
          final pending = coordinator.runSystemPrompt(() => reply.future);
          final authorization = coordinator.authorizationGeneration;
          coordinator.inactive();
          now += const Duration(minutes: 2);
          expect(gate.allowsOperations, isFalse);
          expect(coordinator.authorizationGeneration, authorization);
          coordinator.resume();
          reply.complete();
          await pending;
          expect(coordinator.state.isLocked, isFalse);
          expect(gate.allowsOperations, isTrue);

          // A new interruption after the dialog is no longer owned, even
          // when it immediately follows the dialog's foreground handoff.
          coordinator.inactive();
          now += const Duration(seconds: 31);
          coordinator.resume();
          expect(coordinator.state.isLocked, isTrue);
        });

        test(
          'finished owned prompt cannot leave access while away, immediate=$immediate',
          () async {
            attach();
            if (immediate) coordinator.setBackgroundGrace(Duration.zero);
            final reply = Completer<void>();
            final pending = coordinator.runSystemPrompt(() => reply.future);
            coordinator.inactive();
            now += const Duration(seconds: 31);
            reply.complete();
            await pending;
            coordinator.resume();
            expect(coordinator.state.isLocked, isTrue);
            expect(gate.allowsOperations, isFalse);
          },
        );

        test(
          'verified inactive-only return is bounded, immediate=$immediate',
          () async {
            attach();
            if (immediate) coordinator.setBackgroundGrace(Duration.zero);
            final reply = Completer<void>();
            final pending = coordinator.runSystemPrompt(
              () => reply.future,
              waitForForeground: true,
            );
            coordinator.inactive();
            now += const Duration(seconds: 31);
            reply.complete();
            await Future<void>.delayed(Duration.zero);
            expect(gate.allowsOperations, isFalse);
            coordinator.resume();
            await pending;
            expect(coordinator.state.isLocked, isFalse);
            expect(gate.allowsOperations, isTrue);
          },
        );
      }

      for (final seconds in [0, 29, 31]) {
        test('picker inactive-only return counts $seconds seconds', () async {
          attach();
          if (seconds == 0) coordinator.setBackgroundGrace(Duration.zero);
          final reply = Completer<String>();
          final pending = coordinator.runSystemDialogAwaitingForeground(
            () => reply.future,
          );
          coordinator.inactive();
          now += Duration(seconds: seconds);
          reply.complete('synthetic-destination-token');
          await Future<void>.delayed(Duration.zero);
          coordinator.resume();
          expect(await pending, 'synthetic-destination-token');
          expect(coordinator.state.isLocked, seconds != 29);
          expect(gate.allowsOperations, seconds == 29);
        });
      }

      test('nested owned scopes retain the picker deadline', () async {
        attach();
        final outerReply = Completer<void>();
        final outer = coordinator.runSystemPrompt(() => outerReply.future);
        final pickerReply = Completer<String>();
        final picker = coordinator.runSystemDialogAwaitingForeground(
          () => pickerReply.future,
        );
        coordinator.inactive();
        now += const Duration(seconds: 25);
        outerReply.complete();
        await outer;
        expect(coordinator.hasSystemPrompt, isTrue);
        coordinator.inactive();
        now += const Duration(seconds: 6);
        pickerReply.complete('synthetic-destination-token');
        await Future<void>.delayed(Duration.zero);
        coordinator.resume();
        expect(await picker, 'synthetic-destination-token');
        expect(coordinator.hasSystemPrompt, isFalse);
        expect(coordinator.state.isLocked, isTrue);
        expect(gate.allowsOperations, isFalse);
      });

      test('manual lock revokes native completion during inactivity', () async {
        attach();
        final reply = Completer<void>();
        final pending = coordinator.runSystemPrompt(
          () => reply.future,
          waitForForeground: true,
        );
        final rejected = expectLater(
          pending,
          throwsA(isA<WalletAccessException>()),
        );
        coordinator.inactive();
        coordinator.lock();
        reply.complete();
        await rejected;
        coordinator.resume();
        expect(coordinator.state.isLocked, isTrue);
        expect(coordinator.beginUnlock(automatic: true), isNull);
      });

      for (final background in [false, true]) {
        test(
          'new interruption revokes completed unlock, background=$background',
          () {
            attach(authenticated: false);
            final attempt = coordinator.beginUnlock()!;
            coordinator.inactive();
            expect(coordinator.completeUnlock(attempt), isTrue);
            if (background) {
              coordinator.background();
            } else {
              coordinator.inactive();
            }
            coordinator.resume();
            expect(coordinator.state.isLocked, isTrue);
            expect(gate.allowsOperations, isFalse);
            expect(coordinator.completeUnlock(attempt), isFalse);
          },
        );
      }
    });

    test('system prompt marking does not renew background grace', () async {
      attach();
      final prompt = Completer<void>();
      final result = coordinator.runSystemPrompt(() => prompt.future);
      coordinator.background();
      now += const Duration(seconds: 31);
      coordinator.resume();
      expect(coordinator.state.isLocked, isTrue);
      prompt.complete();
      await result;
      expect(coordinator.hasSystemPrompt, isFalse);
    });

    test('native challenge completes on return with immediate lock', () {
      attach(authenticated: false);
      coordinator.setBackgroundGrace(Duration.zero);
      final attempt = coordinator.beginUnlock()!;
      coordinator.inactive();
      coordinator.background();
      now += const Duration(seconds: 45);
      expect(coordinator.completeUnlock(attempt), isTrue);
      expect(coordinator.state.coversContent, isTrue);
      expect(gate.allowsOperations, isFalse);
      coordinator.resume();
      expect(coordinator.state.isLocked, isFalse);
      expect(gate.allowsOperations, isTrue);

      coordinator.background();
      coordinator.resume();
      expect(coordinator.state.isLocked, isTrue);
    });

    test(
      'verified sign-in attaches on immediate native-dialog return',
      () async {
        attach();
        coordinator.setBackgroundGrace(Duration.zero);
        final generation = coordinator.authorizationGeneration;
        await coordinator.runSystemPrompt(() async {
          coordinator.background();
          expect(coordinator.authorizationGeneration, generation);
          coordinator.attachWallet(
            'wallet-a',
            requiresAuthentication: true,
            authenticated: true,
            sessionIdentity: Object(),
          );
        });
        coordinator.resume();
        expect(coordinator.state.isLocked, isFalse);
        expect(gate.allowsOperations, isTrue);
      },
    );

    test('completed background challenge does not grant delayed return', () {
      attach(authenticated: false);
      final attempt = coordinator.beginUnlock()!;
      coordinator.background();
      expect(coordinator.completeUnlock(attempt), isTrue);
      now += const Duration(seconds: 40);
      coordinator.resume();
      expect(coordinator.state.isLocked, isTrue);
      expect(gate.allowsOperations, isFalse);
    });

    test('device lock revokes a pending challenge immediately', () {
      attach(authenticated: false);
      final attempt = coordinator.beginUnlock()!;
      coordinator.deviceLocked();
      expect(coordinator.completeUnlock(attempt), isFalse);
      coordinator.resume();
      expect(coordinator.state.isLocked, isTrue);
    });

    test('switch and same-wallet reauthentication revoke old challenge', () {
      attach(authenticated: false);
      final old = coordinator.beginUnlock()!;
      coordinator.attachWallet('entry-b', requiresAuthentication: true);
      expect(coordinator.completeUnlock(old), isFalse);
      final sameWalletOld = coordinator.beginUnlock()!;
      coordinator.attachWallet(
        'entry-b',
        requiresAuthentication: true,
        sessionIdentity: Object(),
      );
      expect(coordinator.completeUnlock(sameWalletOld), isFalse);
      expect(coordinator.state.isLocked, isTrue);
    });

    test(
      'secret-view closure is independent of grace and protection',
      () async {
        attach(protected: false);
        var closures = 0;
        final subscription = coordinator.sensitiveViewsMustClose.listen(
          (_) => closures++,
        );
        coordinator.inactive();
        expect(closures, 1);
        coordinator.background();
        expect(closures, 2);
        await subscription.cancel();
      },
    );

    test('unprotected wallet never presents a false authentication lock', () {
      attach(protected: false);
      coordinator.background();
      now += const Duration(hours: 2);
      coordinator.resume();
      coordinator.lock();

      expect(coordinator.state.isLocked, isFalse);
      expect(coordinator.state.coversContent, isFalse);
      expect(gate.allowsOperations, isTrue);
      expect(coordinator.beginUnlock(), isNull);
    });

    test('clock discontinuity fails closed instead of extending grace', () {
      now = const Duration(seconds: 100);
      attach();
      coordinator.background();
      now = const Duration(seconds: 20);
      coordinator.resume();
      expect(coordinator.state.isLocked, isTrue);
    });
  });
}
