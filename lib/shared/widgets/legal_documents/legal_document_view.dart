import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class LegalDocumentView extends StatefulWidget {
  const LegalDocumentView({
    super.key,
    required this.document,
    this.padding = const EdgeInsets.all(16),
    this.scrollable = false,
  });

  final LegalDocumentType document;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  @override
  State<LegalDocumentView> createState() => _LegalDocumentViewState();
}

class _LegalDocumentViewState extends State<LegalDocumentView> {
  final ScrollController _scrollController = ScrollController();
  int _requestId = 0;
  LegalDocumentContent? _content;
  Object? _loadingError;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void didUpdateWidget(covariant LegalDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _loadDocument();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_content == null) {
      if (_loadingError != null) {
        return Padding(
          padding: widget.padding,
          child: Text(
            LocaleKeys.legalDocumentLoadError.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }

      return const Center(child: CircularProgressIndicator());
    }

    final markdown = Padding(
      padding: widget.padding,
      child: MarkdownBody(
        data: _content!.markdown,
        selectable: true,
        softLineBreak: true,
        styleSheet: _buildStyleSheet(context),
        onTapLink: (_, String? href, __) {
          if (href == null || href.isEmpty) return;
          unawaited(launchUrlString(href));
        },
      ),
    );

    final Widget body = widget.scrollable
        ? DexScrollbar(
            scrollController: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: markdown,
            ),
          )
        : markdown;

    if (!widget.scrollable) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
          if (_isRefreshing) const SizedBox(height: 12),
          body,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
        if (_isRefreshing) const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    final linkStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );

    return base.copyWith(
      a: linkStyle,
      p: Theme.of(context).textTheme.bodyMedium,
      listBullet: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Future<void> _loadDocument() async {
    final requestId = ++_requestId;
    setState(() {
      _loadingError = null;
      _content = null;
      _isRefreshing = false;
    });

    final repository = context.read<LegalDocumentsRepository>();

    try {
      final initialContent = await repository.loadPreferredContent(
        widget.document,
      );
      if (!mounted || requestId != _requestId) return;

      setState(() {
        _content = initialContent;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;

      setState(() {
        _loadingError = error;
      });
      return;
    }

    if (!mounted || requestId != _requestId) return;

    setState(() {
      _isRefreshing = true;
    });

    final refreshedContent = await repository.refreshFromRemote(
      widget.document,
    );
    if (!mounted || requestId != _requestId) return;

    setState(() {
      _isRefreshing = false;
      if (refreshedContent != null) {
        _content = refreshedContent;
      }
    });
  }
}
