import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/analytics/events/auth_events.dart';
import 'package:web_dex/analytics/onboarding_funnel.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';

/// Records `add()` rather than sending. `logEvent` is an extension that calls
/// `add`, so overriding `add` intercepts both calling conventions.
class _FakeAnalyticsBloc extends Cubit<AnalyticsState>
    implements AnalyticsBloc {
  _FakeAnalyticsBloc() : super(AnalyticsState.initial());

  final List<AnalyticsEvent> addedEvents = [];

  @override
  void add(AnalyticsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension on _FakeAnalyticsBloc {
  List<AnalyticsEventData> get data => addedEvents
      .whereType<AnalyticsSendDataEvent>()
      .map((e) => e.data)
      .toList();

  /// `(event name, step slug)` pairs, which is what the invariants are about.
  List<(String, String)> get trace => data.map((d) {
    final step = d.parameters['step'] as String? ?? '';
    return (d.name, step);
  }).toList();
}

void testOnboardingFunnel() {
  group('OnboardingFunnel', () {
    late _FakeAnalyticsBloc analytics;

    OnboardingFunnel build({int? Function()? walletCount}) => OnboardingFunnel(
      analytics: analytics,
      entryPoint: 'header',
      existingWalletCount: walletCount,
    );

    setUp(() {
      analytics = _FakeAnalyticsBloc();
    });

    tearDown(() => analytics.close());

    test('entering the same step twice views it once', () {
      build()
        ..enter(OnboardingStep.createForm)
        ..enter(OnboardingStep.createForm);

      expect(analytics.trace, [('onboarding_step_viewed', 'create_form')]);
    });

    test('complete then dispose does not also abandon', () {
      build()
        ..enter(OnboardingStep.createForm)
        ..complete()
        ..dispose();

      expect(analytics.trace, [
        ('onboarding_step_viewed', 'create_form'),
        ('onboarding_step_completed', 'create_form'),
      ]);
    });

    test('dispose with an open step abandons it', () {
      build()
        ..enter(OnboardingStep.createForm)
        ..dispose();

      expect(analytics.trace, [
        ('onboarding_step_viewed', 'create_form'),
        ('onboarding_step_abandoned', 'create_form'),
      ]);
    });

    test('entering a new step closes the previous one as abandoned', () {
      build()
        ..enter(OnboardingStep.setupActionSelect)
        ..enter(OnboardingStep.createForm)
        ..dispose();

      expect(analytics.trace, [
        ('onboarding_step_viewed', 'setup_action_select'),
        ('onboarding_step_abandoned', 'setup_action_select'),
        ('onboarding_step_viewed', 'create_form'),
        ('onboarding_step_abandoned', 'create_form'),
      ]);
    });

    test('finish suppresses the abandon that dispose would emit', () {
      build()
        ..enter(OnboardingStep.authSubmitted)
        ..finish()
        ..dispose();

      expect(analytics.trace, [('onboarding_step_viewed', 'auth_submitted')]);
    });

    test('enter after finish emits nothing', () {
      final funnel = build()
        ..enter(OnboardingStep.createForm)
        ..complete()
        ..finish();
      analytics.addedEvents.clear();

      funnel
        ..enter(OnboardingStep.authSubmitted)
        ..complete()
        ..abandon();

      expect(analytics.trace, isEmpty);
    });

    test('abandon with no open step emits nothing', () {
      build()..abandon();
      expect(analytics.trace, isEmpty);
    });

    test('dispose twice abandons at most once', () {
      build()
        ..enter(OnboardingStep.createForm)
        ..dispose()
        ..dispose();

      expect(
        analytics.trace.where((e) => e.$1 == 'onboarding_step_abandoned'),
        hasLength(1),
      );
    });

    test('flow applies to the event that closes the current step', () {
      build()
        ..enter(OnboardingStep.setupActionSelect)
        ..setFlow(OnboardingFlowKind.create)
        ..complete();

      final completed = analytics.data.last;
      expect(completed.parameters['flow'], 'create');
      // The view fired before the branch was known.
      expect(analytics.data.first.parameters['flow'], 'undecided');
    });

    test('entry_point and step_index ride on every event', () {
      build()
        ..enter(OnboardingStep.walletManagerOpened)
        ..complete();

      for (final event in analytics.data) {
        expect(event.parameters['entry_point'], 'header');
        expect(event.parameters['step_index'], 0);
      }
    });

    test(
      'existing_wallet_count is omitted when unresolved, sent when known',
      () {
        build(walletCount: () => null)..enter(OnboardingStep.createForm);
        expect(
          analytics.data.single.parameters.containsKey('existing_wallet_count'),
          isFalse,
        );

        analytics.addedEvents.clear();
        build(walletCount: () => 0)..enter(OnboardingStep.createForm);
        expect(analytics.data.single.parameters['existing_wallet_count'], 0);
      },
    );

    test('a throwing wallet-count reader never breaks setup', () {
      build(walletCount: () => throw StateError('cache exploded'))
        ..enter(OnboardingStep.createForm);

      expect(analytics.data, hasLength(1));
      expect(
        analytics.data.single.parameters.containsKey('existing_wallet_count'),
        isFalse,
      );
    });
  });
}
