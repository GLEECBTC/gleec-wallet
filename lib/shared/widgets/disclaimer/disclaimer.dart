import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class Disclaimer extends StatefulWidget {
  const Disclaimer({super.key, required this.onClose});
  final Function() onClose;

  @override
  State<Disclaimer> createState() => _DisclaimerState();
}

class _DisclaimerState extends State<Disclaimer> {
  static const String _termsOfServiceAssetPath =
      'assets/legal/Terms of Service.md';
  late final Future<String> _termsOfServiceFuture;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _termsOfServiceFuture = rootBundle.loadString(_termsOfServiceAssetPath);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: MediaQuery.of(context).size.height * 2 / 3,
          child: FutureBuilder<String>(
            future: _termsOfServiceFuture,
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    'Failed to load the Terms of Service.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }

              return Markdown(
                controller: _scrollController,
                selectable: true,
                padding: const EdgeInsets.all(16),
                data: snapshot.data ?? '',
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                onTapLink: (_, String? href, __) {
                  if (href == null || href.isEmpty) return;
                  unawaited(launchUrlString(href));
                },
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('close-disclaimer'),
          onPressed: widget.onClose,
          width: 300,
          text: LocaleKeys.close.tr(),
        ),
      ],
    );
  }
}
