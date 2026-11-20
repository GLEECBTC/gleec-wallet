import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/services/app_update_service/app_update_service.dart';

UpdateVersionInfo _release({
  String version = '0.9.7',
  UpdateStatus status = UpdateStatus.available,
}) => UpdateVersionInfo(
  version: version,
  status: status,
  changelog: 'Public release notes',
  downloadUrl: 'https://github.com/GLEECBTC/gleec-wallet/releases/latest',
);

class _Updates extends AppUpdateService {
  UpdateVersionInfo info = _release();
  Completer<UpdateVersionInfo?>? pending;
  int calls = 0;
  @override
  Future<UpdateVersionInfo?> getUpdateInfo() async {
    calls++;
    return pending?.future ?? info;
  }
}

class _Prompt {
  _Prompt(this.info, this.accept, this.cancel, this.dismiss);
  final UpdateVersionInfo info;
  final VoidCallback accept;
  final VoidCallback cancel;

  /// The popup leaving the screen, as the system back gesture does it: with
  /// neither button pressed.
  final VoidCallback dismiss;
}

class _Harness {
  _Harness({Future<String> Function()? currentVersion}) {
    bloc = UpdateBloc(
      service: updates,
      currentVersion: currentVersion ?? () async => '0.9.6',
      presentPopup:
          (info, {required onAccept, required onCancel, required onDismiss}) {
            if (!canPresent) return false;
            prompts.add(_Prompt(info, onAccept, onCancel, onDismiss));
            return true;
          },
    );
    addTearDown(bloc.dispose);
  }
  final updates = _Updates();
  final prompts = <_Prompt>[];

  /// False while no scaffold exists to show the popup on.
  bool canPresent = true;
  late final UpdateBloc bloc;
}

void main() {
  group('Optional update dismissal across route remounts', () {
    testWidgets('a failed initial check can be retried', (tester) async {
      var versionReads = 0;
      final harness = _Harness(
        currentVersion: () async {
          if (versionReads++ == 0) throw StateError('Version unavailable');
          return '0.9.6';
        },
      );
      await expectLater(harness.bloc.init(), throwsStateError);
      await harness.bloc.init();
      expect(harness.prompts, hasLength(1));
      await tester.pump(const Duration(minutes: 5));
      expect(harness.updates.calls, 2);
      harness.bloc.dispose();
    });

    testWidgets(
      'dismissed release stays dismissed after init and periodic checks',
      (tester) async {
        final harness = _Harness();
        await harness.bloc.init();
        expect(harness.prompts, hasLength(1));
        harness.prompts.single.cancel();
        await harness.bloc.init();
        await harness.bloc.init();
        expect(
          harness.updates.calls,
          1,
          reason: 'routing must not restart the checker',
        );
        await tester.pump(const Duration(minutes: 5));
        expect(harness.updates.calls, 2);
        expect(harness.prompts, hasLength(1));
        harness.bloc.dispose();
      },
    );

    testWidgets('a genuinely newer optional release can still be offered', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.bloc.init();
      harness.prompts.single.cancel();
      harness.updates.info = _release(version: '0.9.8');
      await tester.pump(const Duration(minutes: 5));
      expect(harness.prompts.map((p) => p.info.version), ['0.9.7', '0.9.8']);
      harness.bloc.dispose();
    });

    testWidgets(
      'required policy overrides an optional dismissal of the same release',
      (tester) async {
        final harness = _Harness();
        await harness.bloc.init();
        harness.prompts.single.cancel();
        harness.updates.info = _release(status: UpdateStatus.required);
        await tester.pump(const Duration(minutes: 5));
        expect(harness.prompts, hasLength(2));
        expect(harness.prompts.last.info.status, UpdateStatus.required);
        // The required popup has no cancel control. Even an external caller
        // invoking that callback must not suppress the mandatory policy.
        harness.prompts.last.cancel();
        await tester.pump(const Duration(minutes: 5));
        expect(harness.prompts, hasLength(3));
        expect(harness.prompts.last.info.status, UpdateStatus.required);
        harness.bloc.dispose();
      },
    );

    testWidgets('concurrent init calls share one pending check and one timer', (
      tester,
    ) async {
      final harness = _Harness();
      final pending = Completer<UpdateVersionInfo?>();
      harness.updates.pending = pending;
      final first = harness.bloc.init();
      await tester.pump();
      await harness.bloc.init();
      await harness.bloc.init();
      expect(harness.updates.calls, 1);
      pending.complete(_release());
      await tester.pump();
      await first;
      expect(harness.prompts, hasLength(1));
      harness.updates.pending = null;
      await tester.pump(const Duration(minutes: 5));
      expect(harness.updates.calls, 2);
      expect(harness.prompts, hasLength(1));
      harness.bloc.dispose();
    });

    testWidgets('a slow periodic response cannot overlap another check', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.bloc.init();
      harness.prompts.single.cancel();
      final pending = Completer<UpdateVersionInfo?>();
      harness.updates.pending = pending;
      await tester.pump(const Duration(minutes: 5));
      expect(harness.updates.calls, 2);
      await tester.pump(const Duration(minutes: 5));
      expect(harness.updates.calls, 2);
      pending.complete(_release());
      await tester.pump();
      harness.updates.pending = null;
      await tester.pump(const Duration(minutes: 5));
      expect(harness.updates.calls, 3);
      expect(harness.prompts, hasLength(1));
      harness.bloc.dispose();
    });

    testWidgets(
      'disposing during a check cannot show a dialog or restart polling',
      (tester) async {
        final harness = _Harness();
        final pending = Completer<UpdateVersionInfo?>();
        harness.updates.pending = pending;
        final initializing = harness.bloc.init();
        await tester.pump();
        harness.bloc.dispose();
        pending.complete(_release());
        await tester.pump();
        await initializing;
        await harness.bloc.init();
        await tester.pump(const Duration(minutes: 10));
        expect(harness.prompts, isEmpty);
        expect(harness.updates.calls, 1);
      },
    );

    testWidgets(
      'a popup that could not be shown is offered on the next check',
      (tester) async {
        final harness = _Harness()..canPresent = false;
        await harness.bloc.init();
        expect(harness.prompts, isEmpty);

        harness.canPresent = true;
        await tester.pump(const Duration(minutes: 5));
        expect(harness.prompts, hasLength(1));
        harness.bloc.dispose();
      },
    );

    testWidgets(
      'a required update returns after the system back gesture closes it',
      (tester) async {
        final harness = _Harness();
        harness.updates.info = _release(status: UpdateStatus.required);
        await harness.bloc.init();
        await tester.pump(const Duration(minutes: 5));
        expect(
          harness.prompts,
          hasLength(1),
          reason: 'an open popup must not be stacked',
        );

        harness.prompts.single.dismiss();
        await tester.pump(const Duration(minutes: 5));
        expect(harness.prompts, hasLength(2));
        harness.bloc.dispose();
      },
    );

    testWidgets(
      'the back gesture on an optional update is a remind-later, not the end '
      'of update offers',
      (tester) async {
        final harness = _Harness();
        await harness.bloc.init();
        harness.prompts.single.dismiss();
        await tester.pump(const Duration(minutes: 5));
        expect(harness.prompts, hasLength(1));

        harness.updates.info = _release(version: '0.9.8');
        await tester.pump(const Duration(minutes: 5));
        expect(harness.prompts.map((p) => p.info.version), ['0.9.7', '0.9.8']);
        harness.bloc.dispose();
      },
    );

    testWidgets('closing after "update now" keeps the release on offer', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.bloc.init();
      harness.prompts.single
        ..accept()
        ..dismiss();
      await tester.pump(const Duration(minutes: 5));
      expect(harness.prompts, hasLength(2));
      harness.bloc.dispose();
    });

    testWidgets(
      'dismissal does not suppress the release in a new app session',
      (tester) async {
        final first = _Harness();
        await first.bloc.init();
        first.prompts.single.cancel();
        first.bloc.dispose();
        final next = _Harness();
        await next.bloc.init();
        expect(next.prompts, hasLength(1));
        next.bloc.dispose();
      },
    );
  });
}
