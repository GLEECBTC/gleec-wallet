import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

/// Opens the slippage setting for [bloc]'s cross-network routes.
Future<void> showSwapSlippageSheet(BuildContext context, UnifiedSwapBloc bloc) {
  return showSwapSheet<void>(
    context: context,
    label: LocaleKeys.swapSlippageTitle.tr(),
    builder: (_) => SwapSlippageSheet(
      initial: bloc.state.slippage,
      onSave: (slippage) {
        bloc.add(UnifiedSwapSlippageChanged(slippage));
        swapAnnounce(
          context,
          LocaleKeys.swapAnnounceSlippage.tr(args: [slippageText(slippage)]),
        );
      },
    ),
  );
}

/// [fraction] as a percentage to at most two places: 0.5%, 0.05%, 1%.
String slippageText(double fraction) {
  final percent = (fraction * 100).toStringAsFixed(2);
  return '${percent.replaceFirst(RegExp(r'\.?0+$'), '')}%';
}

/// The slippage in one line, with the way to change it.
class SwapSlippageSummary extends StatelessWidget {
  const SwapSlippageSummary({
    required this.slippage,
    required this.onChange,
    super.key,
  });

  final double slippage;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final summary = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${LocaleKeys.swapSlippageTitle.tr()} · '
            '${slippageText(slippage)}',
            style: SwapText.strong(context).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            LocaleKeys.swapSlippageSummary.tr(args: [slippageText(slippage)]),
            style: SwapText.small(context),
          ),
        ],
      ),
    );
    final change = SwapLinkButton(
      label: LocaleKeys.swapSlippageChange.tr(),
      onPressed: onChange,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth / scale < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [summary, change],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summary),
            const SizedBox(width: 8),
            change,
          ],
        );
      },
    );
  }
}

enum _Choice { half, one, two, custom }

/// Chooses how far a cross-network route may fill below its expected amount.
class SwapSlippageSheet extends StatefulWidget {
  const SwapSlippageSheet({
    required this.initial,
    required this.onSave,
    super.key,
  });

  final double initial;
  final ValueChanged<double> onSave;

  @override
  State<SwapSlippageSheet> createState() => _SwapSlippageSheetState();
}

class _SwapSlippageSheetState extends State<SwapSlippageSheet> {
  static const _presets = {
    _Choice.half: 0.005,
    _Choice.one: 0.01,
    _Choice.two: 0.02,
  };

  late _Choice _choice;
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    final preset = _presets.entries
        .where((entry) => entry.value == widget.initial)
        .firstOrNull;
    _choice = preset?.key ?? _Choice.custom;
    _custom = TextEditingController(
      text: preset == null
          ? slippageText(widget.initial).replaceFirst('%', '')
          : '',
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  double? get _value {
    final preset = _presets[_choice];
    if (preset != null) return preset;
    final percent = double.tryParse(_custom.text.trim().replaceAll(',', '.'));
    if (percent == null) return null;
    final fraction = percent / 100;
    if (fraction < swapMinSlippage || fraction > swapMaxSlippage) return null;
    return fraction;
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final String? warning;
    if (value == null) {
      warning = null;
    } else if (value > 0.01) {
      warning = LocaleKeys.swapSlippageHigh.tr();
    } else if (value < 0.001) {
      warning = LocaleKeys.swapSlippageLow.tr();
    } else {
      warning = null;
    }
    final invalid =
        _choice == _Choice.custom &&
        _custom.text.trim().isNotEmpty &&
        value == null;

    return SwapSheetScaffold(
      title: LocaleKeys.swapSlippageTitle.tr(),
      subtitle: LocaleKeys.swapSlippageBody.tr(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwapFilterBar<_Choice>(
            values: _Choice.values,
            selected: _choice,
            semanticLabel: LocaleKeys.swapSlippageTitle.tr(),
            labelOf: (choice) => switch (choice) {
              _Choice.custom => LocaleKeys.swapSlippageCustom.tr(),
              _ => slippageText(_presets[choice]!),
            },
            onChanged: (choice) => setState(() => _choice = choice),
          ),
          if (_choice == _Choice.custom) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _custom,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: LocaleKeys.swapSlippageCustomLabel.tr(),
                suffixText: '%',
                errorText: invalid ? LocaleKeys.swapSlippageInvalid.tr() : null,
                errorMaxLines: 4,
              ),
            ),
          ],
          if (warning != null) ...[
            const SizedBox(height: 14),
            SwapCallout(tone: SwapTone.warning, message: warning),
          ],
        ],
      ),
      footer: SwapButton(
        label: value == null
            ? LocaleKeys.swapSlippageSaveNone.tr()
            : LocaleKeys.swapSlippageSave.tr(args: [slippageText(value)]),
        onPressed: value == null
            ? null
            : () {
                widget.onSave(value);
                Navigator.of(context).maybePop();
              },
      ),
    );
  }
}
