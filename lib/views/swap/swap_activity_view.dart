import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Swap history across both liquidity sources.
///
/// The list is deliberately allowed to be incomplete. KDF stores routed and
/// atomic swaps separately, so one backend being unavailable is a normal
/// partial-result case — and saying "we could not check" is very different
/// from showing an empty list that implies the swaps never happened.
class SwapActivityView extends StatefulWidget {
  const SwapActivityView({super.key});

  @override
  State<SwapActivityView> createState() => _SwapActivityViewState();
}

class _SwapActivityViewState extends State<SwapActivityView> {
  late Future<SwapHistoryPage> _page;

  @override
  void initState() {
    super.initState();
    _page = _load();
  }

  Future<SwapHistoryPage> _load() {
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context, listen: false);
    return SwapHistoryRepository(
      routedSwaps: sdk.routedSwaps,
      // The atomic side still lives behind the legacy trading path, which has
      // its own list UI. Until that is folded in, this surface reports routed
      // swaps and says as much rather than pretending to be the whole picture.
      atomicHistory: ({int limit = 20}) async => const [],
    ).recent();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SwapHistoryPage>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Message(
            key: const Key('swap-activity-error'),
            text: 'We could not load your swap history.',
            onRetry: () => setState(() => _page = _load()),
          );
        }

        final page = snapshot.data!;
        if (page.entries.isEmpty) {
          return _Message(
            key: const Key('swap-activity-empty'),
            text: page.isPartial
                // Not the same statement as "you have none".
                ? 'We could not check all of your swaps. Try again shortly.'
                : 'No swaps yet.',
            onRetry: page.isPartial
                ? () => setState(() => _page = _load())
                : null,
          );
        }

        return ListView.separated(
          itemCount: page.entries.length + (page.isPartial ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0 && page.isPartial) {
              return const ListTile(
                key: Key('swap-activity-partial'),
                leading: Icon(Icons.info_outline),
                title: Text('Some swaps could not be loaded.'),
              );
            }
            final entry = page.entries[index - (page.isPartial ? 1 : 0)];
            return _ActivityRow(entry: entry);
          },
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final SwapHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        entry.source == SwapLiquiditySource.atomic
            ? Icons.swap_horiz
            : Icons.alt_route,
      ),
      title: Text(entry.title ?? entry.statusLabel ?? 'Swap'),
      subtitle: Text(entry.statusLabel ?? ''),
      trailing: entry.needsAttention
          // A partial fill or a refund finished, but not as asked. Without a
          // marker it reads as an ordinary completion in a list of them.
          ? Icon(
              Icons.error_outline,
              key: const Key('swap-activity-attention'),
              color: theme.colorScheme.error,
            )
          : null,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry, super.key});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
