import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:web_dex/bloc/bitrefill/bloc/bitrefill_bloc.dart';
import 'package:web_dex/views/bitrefill/bitrefill_button_view.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// A button that opens the provided url in an embedded InAppWebview widget.
/// This widget uses the flutter_inappwebview package to open the url using
/// platform-specific webview implementations to embed the website inside a
/// widget.
///
/// NOTE: this widget only works on Web, Android, iOS, and macOS (for now).
class BitrefillInAppWebviewButton extends StatefulWidget {
  /// [onMessage] is called when a message is received from the webview.
  /// The [enabled] property determines if the button is clickable.
  /// The [windowTitle] property is used as the title of the window.
  /// The [url] property is the URL to open in the window.
  /// The [tooltip] property is used to show a tooltip message when hovering or when button is disabled.
  /// [onBeforeOpen] resolves the exact URL after any pre-launch selection.
  const BitrefillInAppWebviewButton({
    required this.url,
    required this.windowTitle,
    required this.enabled,
    required this.onMessage,
    super.key,
    this.tooltip,
    this.onBeforeOpen,
  });

  /// The title of the pop-up browser window.
  final String windowTitle;

  /// The URL to open in the pop-up browser window.
  final String url;

  /// Determines if the button is enabled.
  final bool enabled;

  /// The callback function that is called when a message is received from the
  /// webview as a console message.
  final dynamic Function(String) onMessage;

  /// Optional tooltip message to show when hovering or when button is disabled.
  final String? tooltip;

  /// Optional callback invoked before opening. Returning null cancels launch.
  final Future<String?> Function()? onBeforeOpen;

  @override
  BitrefillInAppWebviewButtonState createState() =>
      BitrefillInAppWebviewButtonState();
}

class BitrefillInAppWebviewButtonState
    extends State<BitrefillInAppWebviewButton> {
  InAppWebViewController? webViewController;
  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    mediaPlaybackRequiresUserGesture: false,
    iframeAllow: 'same-origin; popups; scripts; forms',
    iframeAllowFullscreen: false,
  );

  @override
  Widget build(BuildContext context) {
    return BlocListener<BitrefillBloc, BitrefillState>(
      listener: (BuildContext context, BitrefillState state) {
        if (state is BitrefillPaymentInProgress) {
          // Close the browser window when a payment is in progress.
        }
      },
      child: BitrefillButtonView(
        onPressed: widget.enabled ? _handlePress : null,
        tooltip: widget.tooltip,
      ),
    );
  }

  Future<void> _handlePress() async {
    final callback = widget.onBeforeOpen;
    final resolvedUrl = callback == null ? widget.url : await callback();
    if (!mounted || resolvedUrl == null || resolvedUrl.trim().isEmpty) return;

    await _openDialog(resolvedUrl);
  }

  Future<void> _openDialog(String url) async {
    if (kIsWeb) {
      await _showWebDialog(url);
    } else {
      await _showFullScreenDialog(url);
    }
  }

  Future<void> _showWebDialog(String url) async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final size = MediaQuery.of(context).size;
        final width = size.width * 0.8;
        final height = size.height * 0.8;

        return AlertDialog(
          title: Text(LocaleKeys.alertDialogBitrefill.tr()),
          content: SizedBox(
            width: width,
            height: height,
            child: ScreenshotSensitive(
              child: InAppWebView(
                key: const Key('bitrefill-inappwebview'),
                initialUrlRequest: _createUrlRequest(url),
                initialSettings: settings,
                onWebViewCreated: _onCreated,
                onConsoleMessage: _onConsoleMessage,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(LocaleKeys.close.tr()),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFullScreenDialog(String url) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.windowTitle),
              foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
              elevation: 0,
            ),
            body: SafeArea(
              child: ScreenshotSensitive(
                child: InAppWebView(
                  key: const Key('bitrefill-inappwebview'),
                  initialUrlRequest: _createUrlRequest(url),
                  initialSettings: settings,
                  onWebViewCreated: _onCreated,
                  onConsoleMessage: _onConsoleMessage,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: use_setters_to_change_properties
  void _onCreated(InAppWebViewController controller) {
    webViewController = controller;
  }

  void _onConsoleMessage(
    InAppWebViewController controller,
    ConsoleMessage consoleMessage,
  ) {
    widget.onMessage(consoleMessage.message);
  }

  URLRequest _createUrlRequest(String url) {
    return URLRequest(url: WebUri(url));
  }
}
