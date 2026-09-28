part of 'swap_shell.dart';

/// The pill navigation between Swap, Activity and Advanced.
class _SwapNavigation extends StatelessWidget {
  const _SwapNavigation({required this.selected, required this.onSelected});

  final SwapDestination selected;
  final ValueChanged<SwapDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final registry = context.read<SwapServices?>()?.registry;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SwapGeometry.contentWidth,
            ),
            child: StreamBuilder<List<SwapExecutionSnapshot>>(
              stream: registry?.executions,
              builder: (context, _) {
                final active = registry?.activeCount ?? 0;
                final attention = registry?.unacknowledgedAttentionCount ?? 0;
                return Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Row(
                    key: const Key('swap-destination-switcher'),
                    children: [
                      for (final destination in SwapDestination.values) ...[
                        Expanded(
                          child: _NavItem(
                            destination: destination,
                            selected: destination == selected,
                            active: destination == SwapDestination.activity
                                ? active
                                : 0,
                            attention: destination == SwapDestination.activity
                                ? attention
                                : 0,
                            onTap: () => onSelected(destination),
                          ),
                        ),
                        if (destination != SwapDestination.values.last)
                          const SizedBox(width: 4),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.active,
    required this.attention,
    required this.onTap,
  });

  final SwapDestination destination;
  final bool selected;
  final int active;
  final int attention;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final (label, icon) = switch (destination) {
      SwapDestination.swap => (LocaleKeys.swap.tr(), Icons.swap_horiz_rounded),
      SwapDestination.activity => (
        LocaleKeys.swapNavActivity.tr(),
        Icons.schedule_rounded,
      ),
      SwapDestination.advanced => (
        LocaleKeys.swapNavAdvanced.tr(),
        Icons.show_chart_rounded,
      ),
    };
    final foreground = selected ? palette.text : palette.textSecondary;
    final badge = active + attention;
    // The label replaces the pill's own text, so the tap is given again.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: true,
      label: [
        label,
        if (active > 0) LocaleKeys.swapNavActiveCount.tr(args: ['$active']),
        if (attention > 0) LocaleKeys.swapNavNeedsAttention.tr(),
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? palette.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Icons give way first when three pills share a phone.
                  final showIcon = constraints.maxWidth >= 112;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showIcon) ...[
                        Icon(icon, size: 18, color: foreground),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            key: Key('swap-destination-${destination.name}'),
                            maxLines: 1,
                            style: SwapText.strong(
                              context,
                            ).copyWith(color: foreground, fontSize: 14),
                          ),
                        ),
                      ),
                      if (badge > 0) ...[
                        const SizedBox(width: 6),
                        SwapCountDot(
                          count: badge,
                          tone: attention > 0 ? SwapTone.warning : null,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
