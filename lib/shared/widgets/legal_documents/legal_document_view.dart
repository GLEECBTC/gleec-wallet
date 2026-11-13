import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web_dex/bloc/legal_documents/legal_document_bloc.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_notice.dart';

class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.document,
    this.padding = const EdgeInsets.all(16),
    this.scrollable = false,
    this.content,
    this.repository,
  });
  final LegalDocumentType document;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final LegalDocumentContent? content;
  final LegalDocumentsRepository? repository;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey((document, content)),
    create: (_) => LegalDocumentBloc(
      repository ?? context.read<LegalDocumentsRepository>(),
      document,
      content: content,
    )..add(const LegalDocumentRequested()),
    child: _LegalDocumentBody(padding: padding, scrollable: scrollable),
  );
}

class _LegalDocumentBody extends StatefulWidget {
  const _LegalDocumentBody({required this.padding, required this.scrollable});
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  @override
  State<_LegalDocumentBody> createState() => _LegalDocumentBodyState();
}

class _LegalDocumentBodyState extends State<_LegalDocumentBody> {
  final _scrollController = ScrollController();
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LegalDocumentBloc, LegalDocumentContent>(
        builder: (context, content) {
          final theme = Theme.of(context);
          final body = Padding(
            padding: widget.padding,
            child: content.isAvailable
                ? MarkdownBody(
                    data: content.markdown,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium,
                      listBullet: theme.textTheme.bodyMedium,
                      a: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    onTapLink: (_, href, __) {
                      if (href != null && href.isNotEmpty) {
                        unawaited(launchUrlString(href));
                      }
                    },
                  )
                : LegalDocumentNotice(
                    status: content.status,
                    onRetry: () => context.read<LegalDocumentBloc>().add(
                      const LegalDocumentRequested(retry: true),
                    ),
                  ),
          );
          return widget.scrollable
              ? DexScrollbar(
                  scrollController: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: body,
                  ),
                )
              : body;
        },
      );
}
