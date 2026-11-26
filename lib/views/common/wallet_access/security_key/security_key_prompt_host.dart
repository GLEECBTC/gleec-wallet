import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';
import 'package:web_dex/views/common/wallet_access/security_key/security_key_prompt_sheet.dart';

/// Draws the security-key sheet over [child]. Place it above the app lock
/// boundary: a passkey unlock starts from the lock cover, which an ordinary
/// dialog would sit under.
class SecurityKeyPromptHost extends StatefulWidget {
  const SecurityKeyPromptHost({required this.child, this.prompts, super.key});

  final Widget child;
  final SecurityKeyPrompts? prompts;

  @override
  State<SecurityKeyPromptHost> createState() => _SecurityKeyPromptHostState();
}

class _SecurityKeyPromptHostState extends State<SecurityKeyPromptHost> {
  late SecurityKeyPrompts _prompts;
  StreamSubscription<SecurityKeyPrompt?>? _changes;
  SecurityKeyPrompt? _prompt;
  FocusNode? _focusBefore;

  @override
  void initState() {
    super.initState();
    _attach(widget.prompts ?? SecurityKeyPrompts.instance);
  }

  @override
  void didUpdateWidget(SecurityKeyPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prompts = widget.prompts ?? SecurityKeyPrompts.instance;
    if (identical(prompts, _prompts)) return;
    _detach();
    _attach(prompts);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach(SecurityKeyPrompts prompts) {
    _prompts = prompts..attachHost();
    _prompt = prompts.current;
    _changes = prompts.changes.listen(_onPrompt);
  }

  void _detach() {
    unawaited(_changes?.cancel());
    _prompts.detachHost();
  }

  void _onPrompt(SecurityKeyPrompt? prompt) {
    if (!mounted) return;
    if (_prompt == null && prompt != null) {
      _focusBefore = FocusManager.instance.primaryFocus;
    }
    final closing = _prompt != null && prompt == null;
    setState(() => _prompt = prompt);
    if (closing) {
      final before = _focusBefore;
      _focusBefore = null;
      // The sheet's removal would otherwise leave focus on the root scope.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (before != null && before.context != null) before.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prompt = _prompt;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: prompt != null,
          child: ExcludeFocus(
            excluding: prompt != null,
            child: IgnorePointer(ignoring: prompt != null, child: widget.child),
          ),
        ),
        if (prompt != null)
          Positioned.fill(
            child: BlockSemantics(
              child: _PromptOverlay(
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                  },
                  child: Actions(
                    actions: {
                      DismissIntent: CallbackAction<DismissIntent>(
                        onInvoke: (_) => _prompts.cancel(),
                      ),
                    },
                    child: SecurityKeyPromptSheet(
                      key: const Key('security-key-sheet'),
                      prompt: prompt,
                      prompts: _prompts,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The sheet can sit above the app's Navigator, and its PIN field's
/// selection handles and toolbar need an Overlay of their own.
class _PromptOverlay extends StatefulWidget {
  const _PromptOverlay({required this.child});

  final Widget child;

  @override
  State<_PromptOverlay> createState() => _PromptOverlayState();
}

class _PromptOverlayState extends State<_PromptOverlay> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_PromptOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
