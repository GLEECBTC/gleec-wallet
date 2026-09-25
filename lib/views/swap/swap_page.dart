import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

/// The Swap destination: the form, its review, and the swap just started.
///
/// On a wide screen the review opens beside the form rather than over it, so
/// the numbers being consented to stay next to the inputs that produced them.
class SwapPage extends StatelessWidget {
  const SwapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
      buildWhen: (previous, current) =>
          previous.view != current.view ||
          previous.activeExecutionId != current.activeExecutionId,
      builder: (context, state) {
        switch (state.view) {
          case UnifiedSwapView.form:
            return const SwapEntryView();
          case UnifiedSwapView.review:
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < SwapGeometry.sidePanelBreakpoint) {
                  return const SwapReviewView();
                }
                final width = (constraints.maxWidth * 0.42).clamp(
                  280.0,
                  SwapGeometry.panelWidth,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: _SideForm()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 16, 20),
                      child: SizedBox(
                        width: width,
                        child: const _ReviewPanel(),
                      ),
                    ),
                  ],
                );
              },
            );
          case UnifiedSwapView.progress:
            final id = state.activeExecutionId;
            if (id == null) return const SwapEntryView();
            return SwapExecutionView(
              key: ValueKey('progress-$id'),
              id: id,
              context: SwapExecutionContext.flow,
            );
        }
      },
    );
  }
}

/// The form beside a review. While the reviewed swap's start is unanswered
/// or lost, the review is the only way on, so the form is set aside.
class _SideForm extends StatelessWidget {
  const _SideForm();

  @override
  Widget build(BuildContext context) {
    final inDoubt = context.select<UnifiedSwapBloc, bool>(
      (bloc) => switch (bloc.state.review?.status) {
        SwapReviewStatus.starting || SwapReviewStatus.unconfirmed => true,
        _ => false,
      },
    );
    return IgnorePointer(
      ignoring: inDoubt,
      child: ExcludeFocus(
        excluding: inDoubt,
        child: ExcludeSemantics(
          excluding: inDoubt,
          child: Opacity(
            opacity: inDoubt ? 0.55 : 1,
            child: const SwapEntryView(panelOpen: true),
          ),
        ),
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel();

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 48,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: const SwapReviewView(inPanel: true),
      ),
    );
  }
}
