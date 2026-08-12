import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/widgets/swap_form.dart';
import 'package:web_dex/views/swap/widgets/swap_progress_view.dart';
import 'package:web_dex/views/swap/widgets/swap_review_sheet.dart';

/// The swap screen.
///
/// One surface over both liquidity sources. Which source fills a given swap is
/// shown but not chosen by the user: the ranking already prefers the better
/// guarantee, and asking someone to pick between "peer-to-peer" and "routed"
/// on every trade is a question most people cannot answer.
class SwapPage extends StatelessWidget {
  const SwapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: switch (state.step) {
            UnifiedSwapStep.fill => const SwapForm(),
            UnifiedSwapStep.confirm => const SwapReviewSheet(),
            UnifiedSwapStep.inProgress ||
            UnifiedSwapStep.complete ||
            UnifiedSwapStep.failed => _ProgressStep(state: state),
          },
        );
      },
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.state});

  final UnifiedSwapState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    if (progress == null) {
      // Between start and the first snapshot. The swap is already recoverable
      // — the SDK resolved its durable id before returning — so this is a
      // rendering gap, not an unknown state.
      return const Center(child: CircularProgressIndicator());
    }

    return SwapProgressView(
      progress: progress,
      onCancel: () => context.read<UnifiedSwapBloc>().add(
        const UnifiedSwapCancelRequested(),
      ),
      onDone: () =>
          context.read<UnifiedSwapBloc>().add(const UnifiedSwapReset()),
    );
  }
}
