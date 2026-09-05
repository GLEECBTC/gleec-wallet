import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:web_dex/bloc/bitrefill/bloc/bitrefill_bloc.dart';
import 'package:web_dex/views/bitrefill/bitrefill_button_view.dart';

/// A button that opens the provided [url] in an InAppBrowser window.
/// This widget uses the flutter_inappwebview package to open a new window.
/// The window is closed when a BitrefillPaymentInProgress event is received.
///
/// NOTE: this widget only works on Web, Android, iOS, and macOS (for now).
class BitrefillInAppBrowserButton extends StatefulWidget {
  /// The [onMessage] is called when a message is received from the webview.
  /// The [enabled] property determines if the button is enabled.
  /// The [windowTitle] property is used as the title of the window.
  /// The [url] property is the URL to open in the window.
  const BitrefillInAppBrowserButton({
    required this.url,
    required this.windowTitle,
    required this.enabled,
    required this.onMessage,
    super.key,
  });

  /// The title of the pop-up browser window.
  final String windowTitle;

  /// The URL to open in the pop-up browser window.
  final String url;

  /// Determines if the button is enabled.
  final bool enabled;

  /// The callback function that is called when a message is received from the
  /// webview.
  final dynamic Function(String) onMessage;

  @override
  BitrefillInAppBrowserButtonState createState() =>
      BitrefillInAppBrowserButtonState();
}

class BitrefillInAppBrowserButtonState
    extends State<BitrefillInAppBrowserButton> {
  CustomInAppBrowser? browser;

  @override
  void initState() {
    super.initState();
    browser = CustomInAppBrowser(onMessage: widget.onMessage);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BitrefillBloc, BitrefillState>(
      listener: (BuildContext context, BitrefillState state) {
        if (state is BitrefillPaymentInProgress) {
          browser?.close();
        }
      },
      child: BitrefillButtonView(
        onPressed: widget.enabled ? _openBrowserWindow : null,
      ),
    );
  }

  Future<void> _openBrowserWindow() async {
    await browser?.openUrlRequest(
      urlRequest: URLRequest(url: WebUri(widget.url)),
    );
  }
}

/// A custom InAppBrowser that calls the [onMessage] callback when a
/// console message is received (`console.log(message)` in JavaScript).
class CustomInAppBrowser extends InAppBrowser {
  CustomInAppBrowser({required this.onMessage}) : super();

  final dynamic Function(String) onMessage;

  @override
  void onConsoleMessage(ConsoleMessage consoleMessage) {
    onMessage(consoleMessage.message);
  }
}
