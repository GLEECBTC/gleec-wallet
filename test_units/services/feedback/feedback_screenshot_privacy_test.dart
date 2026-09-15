import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:feedback/feedback.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/feedback/feedback_capture_session.dart';
import 'package:web_dex/services/feedback/feedback_provider.dart';
import 'package:web_dex/services/feedback/feedback_screenshot_guard.dart';
import 'package:web_dex/services/feedback/feedback_service.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class _RecordingScreenshotProvider implements FeedbackProvider {
  final screenshots = <Uint8List>[];
  String? description;
  Map<String, dynamic>? metadata;

  @override
  bool get isAvailable => true;

  @override
  Future<void> submitFeedback({
    required String description,
    required Uint8List screenshot,
    required String type,
    required Map<String, dynamic> metadata,
    SafeLogAttachment? diagnostics,
  }) async {
    screenshots.add(screenshot);
    this.description = description;
    this.metadata = metadata;
  }
}

FeedbackService _service(_RecordingScreenshotProvider provider) =>
    FeedbackService(
      provider: provider,
      loadMetadata: () async => {},
      loadDiagnostics: () async => SafeLogAttachment.empty(),
    );

UserFeedback _feedback(Uint8List screenshot) => UserFeedback(
  text: 'Synthetic screenshot report',
  screenshot: screenshot,
  extra: {
    'feedback_type': 'bugReport',
    'contact_method': 'email',
    'contact_details': 'tester@example.invalid',
  },
);

Future<Uint8List> _redScreenshot(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 16, 16),
        ui.Paint()..color = const ui.Color(0xffff0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(16, 16);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        return Uint8List.fromList(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    }))!;

Future<void> _expectTransparentPng(WidgetTester tester, Uint8List bytes) =>
    tester.runAsync(() async {
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      // Decode the actual transmitted bytes, including PNG/zlib integrity and
      // the RGBA pixel. A plausible header alone is not a usable replacement.
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 1);
          expect(frame.image.height, 1);
          final rgba = (await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          expect(
            rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
            [0, 0, 0, 0],
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });

const _redChildKey = ValueKey('synthetic-secret-red-child');

Widget _guardHost({
  required GlobalKey boundary,
  required FeedbackController feedback,
  required ScreenshotSensitivityController? sensitivity,
  required VoidCallback onTap,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: boundary,
      child: SizedBox(
        width: 32,
        height: 32,
        child: FeedbackScreenshotGuard(
          feedbackController: feedback,
          sensitivityController: sensitivity,
          child: GestureDetector(
            key: _redChildKey,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: const ColoredBox(color: Color(0xffff0000)),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _expectGuardPixels(
  WidgetTester tester,
  GlobalKey key, {
  required bool masked,
}) async {
  final pixels = (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, 32);
      expect(image.height, 32);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }))!;
  final expected = masked ? [32, 32, 32, 255] : [255, 0, 0, 255];
  for (var offset = 0; offset < pixels.length; offset += 4) {
    expect(
      pixels.sublist(offset, offset + 4),
      expected,
      reason:
          'The entire sensitive child must be masked at pixel ${offset ~/ 4}.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('feedback screenshot capture policy', () {
    test(
      'initial sensitivity stays unsafe after leaving the secret screen',
      () {
        final controller = ScreenshotSensitivityController()..enter();
        addTearDown(controller.dispose);
        final policy = ScreenshotCapturePolicy.capture(controller);
        controller.exit();
        expect(controller.isSensitive, isFalse);
        expect(policy.canIncludeScreenshot(controller), isFalse);
      },
    );

    test(
      'a synchronous enter and exit invalidates an initially safe capture',
      () {
        final controller = ScreenshotSensitivityController();
        addTearDown(controller.dispose);
        final policy = ScreenshotCapturePolicy.capture(controller);
        expect(policy.canIncludeScreenshot(controller), isTrue);
        controller.enter();
        controller.exit();
        expect(controller.isSensitive, isFalse);
        expect(policy.canIncludeScreenshot(controller), isFalse);
      },
    );

    test('missing, replaced and disposed controllers fail closed', () {
      final controller = ScreenshotSensitivityController();
      final replacement = ScreenshotSensitivityController();
      addTearDown(replacement.dispose);
      final policy = ScreenshotCapturePolicy.capture(controller);
      expect(policy.canIncludeScreenshot(null), isFalse);
      expect(policy.canIncludeScreenshot(replacement), isFalse);
      expect(
        ScreenshotCapturePolicy.capture(null).canIncludeScreenshot(controller),
        isFalse,
      );
      controller.dispose();
      expect(policy.canIncludeScreenshot(controller), isFalse);
      expect(
        ScreenshotCapturePolicy.capture(
          controller,
        ).canIncludeScreenshot(controller),
        isFalse,
      );
    });
  });

  group('feedback screenshot submission', () {
    testWidgets(
      'a sensitive capture remains transparent after clearing during the delay',
      (tester) async {
        final controller = ScreenshotSensitivityController()..enter();
        addTearDown(controller.dispose);
        final provider = _RecordingScreenshotProvider();
        final original = await _redScreenshot(tester);
        final session = FeedbackCaptureSession.begin(controller);
        final submitted = session.submit(
          _feedback(original),
          service: _service(provider),
          currentController: () => controller,
        );
        controller.exit();
        await tester.pump(const Duration(milliseconds: 499));
        expect(provider.screenshots, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        expect(await submitted, isTrue);
        await _expectTransparentPng(tester, provider.screenshots.single);
        expect(provider.description, 'Synthetic screenshot report');
        expect(provider.metadata?['contactDetails'], 'tester@example.invalid');
      },
    );

    testWidgets('a safe session preserves the original screenshot bytes', (
      tester,
    ) async {
      final controller = ScreenshotSensitivityController();
      addTearDown(controller.dispose);
      final provider = _RecordingScreenshotProvider();
      final original = await _redScreenshot(tester);
      final session = FeedbackCaptureSession.begin(controller);
      final submitted = session.submit(
        _feedback(original),
        service: _service(provider),
        currentController: () => controller,
        settleDelay: Duration.zero,
      );
      await tester.pump(Duration.zero);
      expect(await submitted, isTrue);
      expect(provider.screenshots.single, same(original));
    });

    testWidgets(
      'a late sensitive entry and exit during submission replaces the captured pixels',
      (tester) async {
        final controller = ScreenshotSensitivityController();
        addTearDown(controller.dispose);
        final provider = _RecordingScreenshotProvider();
        final original = await _redScreenshot(tester);
        final session = FeedbackCaptureSession.begin(controller);
        final submitted = session.submit(
          _feedback(original),
          service: _service(provider),
          currentController: () => controller,
        );
        await tester.pump(const Duration(milliseconds: 250));
        controller.enter();
        controller.exit();
        await tester.pump(const Duration(milliseconds: 250));
        expect(await submitted, isTrue);
        await _expectTransparentPng(tester, provider.screenshots.single);
      },
    );

    for (final transition in ['missing', 'replaced', 'disposed']) {
      testWidgets(
        '$transition controller during submission sends a transparent PNG',
        (tester) async {
          final controller = ScreenshotSensitivityController();
          final replacement = ScreenshotSensitivityController();
          addTearDown(replacement.dispose);
          if (transition != 'disposed') addTearDown(controller.dispose);
          ScreenshotSensitivityController? current = controller;
          final provider = _RecordingScreenshotProvider();
          final original = await _redScreenshot(tester);
          final session = FeedbackCaptureSession.begin(controller);
          final submitted = session.submit(
            _feedback(original),
            service: _service(provider),
            currentController: () => current,
          );
          switch (transition) {
            case 'missing':
              current = null;
            case 'replaced':
              current = replacement;
            case 'disposed':
              controller.dispose();
          }
          await tester.pump(const Duration(milliseconds: 500));
          expect(await submitted, isTrue);
          await _expectTransparentPng(tester, provider.screenshots.single);
        },
      );
    }

    testWidgets(
      'missing controller at capture cannot become safe before submission',
      (tester) async {
        final controller = ScreenshotSensitivityController();
        addTearDown(controller.dispose);
        final provider = _RecordingScreenshotProvider();
        final submitted = FeedbackCaptureSession.begin(null).submit(
          _feedback(await _redScreenshot(tester)),
          service: _service(provider),
          currentController: () => controller,
          settleDelay: Duration.zero,
        );
        await tester.pump(Duration.zero);
        expect(await submitted, isTrue);
        await _expectTransparentPng(tester, provider.screenshots.single);
      },
    );
  });

  group('feedback screenshot rendering', () {
    testWidgets(
      'sensitive pixels and hit testing are masked only during the feedback session',
      (tester) async {
        final feedback = FeedbackController();
        final sensitivity = ScreenshotSensitivityController()..enter();
        final boundary = GlobalKey();
        var taps = 0;
        await tester.pumpWidget(
          _guardHost(
            boundary: boundary,
            feedback: feedback,
            sensitivity: sensitivity,
            onTap: () => taps++,
          ),
        );
        await _expectGuardPixels(tester, boundary, masked: false);
        await tester.tap(find.byKey(_redChildKey));
        expect(taps, 1);

        feedback.show((_) {});
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: true);
        await tester.tap(find.byKey(_redChildKey), warnIfMissed: false);
        expect(taps, 1);
        sensitivity.exit();
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: true);

        feedback.hide();
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: false);
        feedback.show((_) {});
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: false);
        await tester.tap(find.byKey(_redChildKey));
        expect(taps, 2);
        await tester.pumpWidget(const SizedBox());
        feedback.dispose();
        sensitivity.dispose();
      },
    );

    testWidgets(
      'enter and exit before the next frame still masks the entire preview',
      (tester) async {
        final feedback = FeedbackController();
        final sensitivity = ScreenshotSensitivityController();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _guardHost(
            boundary: boundary,
            feedback: feedback,
            sensitivity: sensitivity,
            onTap: () {},
          ),
        );
        feedback.show((_) {});
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: false);
        sensitivity.enter();
        sensitivity.exit();
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: true);
        await tester.pumpWidget(const SizedBox());
        feedback.dispose();
        sensitivity.dispose();
      },
    );

    testWidgets(
      'replacement, missing and disposed sensitivity fail closed in the visible preview',
      (tester) async {
        final feedback = FeedbackController();
        final original = ScreenshotSensitivityController();
        final replacement = ScreenshotSensitivityController();
        final boundary = GlobalKey();
        Future<void> mount(ScreenshotSensitivityController? controller) =>
            tester.pumpWidget(
              _guardHost(
                boundary: boundary,
                feedback: feedback,
                sensitivity: controller,
                onTap: () {},
              ),
            );
        await mount(original);
        feedback.show((_) {});
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: false);
        await mount(replacement);
        await _expectGuardPixels(tester, boundary, masked: true);
        await mount(original);
        await _expectGuardPixels(tester, boundary, masked: true);
        await mount(replacement);
        feedback.hide();
        feedback.show((_) {});
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: false);
        await mount(null);
        await _expectGuardPixels(tester, boundary, masked: true);
        await mount(replacement);
        feedback.hide();
        feedback.show((_) {});
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: false);
        replacement.dispose();
        await tester.pump();
        await _expectGuardPixels(tester, boundary, masked: true);
        await tester.pumpWidget(const SizedBox());
        feedback.dispose();
        original.dispose();
      },
    );

    testWidgets(
      'an already disposed controller masks a newly mounted feedback preview',
      (tester) async {
        final feedback = FeedbackController()..show((_) {});
        final sensitivity = ScreenshotSensitivityController()..dispose();
        final boundary = GlobalKey();
        await tester.pumpWidget(
          _guardHost(
            boundary: boundary,
            feedback: feedback,
            sensitivity: sensitivity,
            onTap: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        await _expectGuardPixels(tester, boundary, masked: true);
        await tester.pumpWidget(const SizedBox());
        feedback.dispose();
      },
    );
  });
}
