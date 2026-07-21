part of 'gnosis_onboarding_widgets.dart';

class _MilestoneRail extends StatelessWidget {
  const _MilestoneRail({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final label = 'gnosisCard.milestones.stepOf'.tr(
      args: [
        '${current + 1}',
        '${_milestoneKeys.length}',
        _milestoneKeys[current.clamp(0, _milestoneKeys.length - 1)].tr(),
      ],
    );
    return Semantics(
      label: label,
      liveRegion: true,
      explicitChildNodes: true,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                LocaleKeys.gnosisCard_title.tr(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              for (var index = 0; index < _milestoneKeys.length; index += 1)
                _MilestoneTile(
                  label: _milestoneKeys[index].tr(),
                  index: index,
                  current: current,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactMilestones extends StatelessWidget {
  const _CompactMilestones({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final label = 'gnosisCard.milestones.stepOf'.tr(
      args: [
        '${current + 1}',
        '${_milestoneKeys.length}',
        _milestoneKeys[current.clamp(0, _milestoneKeys.length - 1)].tr(),
      ],
    );
    return Semantics(
      label: label,
      value: '${current + 1} / ${_milestoneKeys.length}',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (
                var index = 0;
                index < _milestoneKeys.length;
                index += 1
              ) ...[
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: index <= current
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                if (index < _milestoneKeys.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.label,
    required this.index,
    required this.current,
  });

  final String label;
  final int index;
  final int current;

  @override
  Widget build(BuildContext context) {
    final complete = index < current;
    final active = index == current;
    final status = complete
        ? LocaleKeys.gnosisCard_milestones_complete.tr()
        : active
        ? LocaleKeys.gnosisCard_milestones_current.tr()
        : LocaleKeys.gnosisCard_milestones_upcoming.tr();
    final color = active || complete
        ? Theme.of(context).colorScheme.primary
        : _gnosisReadableText(context);
    return Semantics(
      label: '$label, $status',
      selected: active,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: active || complete
                  ? color
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: active || complete
                  ? Theme.of(context).colorScheme.onPrimary
                  : color,
              child: complete
                  ? const Icon(Icons.check, size: 18)
                  : Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _gnosisReadableText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFF5F2F8)
    : const Color(0xFF34495C);

Color _gnosisBorderColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFB8ADBF)
    : const Color(0xFF64798C);
