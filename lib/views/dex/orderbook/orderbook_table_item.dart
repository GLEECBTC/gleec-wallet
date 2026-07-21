import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class OrderbookTableItem extends StatefulWidget {
  const OrderbookTableItem(
    this.order, {
    Key? key,
    required this.volumeFraction,
    this.isSelected = false,
    this.onClick,
  }) : super(key: key);

  final Order order;
  final double volumeFraction;
  final bool isSelected;
  final Function(Order)? onClick;

  @override
  State<OrderbookTableItem> createState() => _OrderbookTableItemState();
}

class _OrderbookTableItemState extends State<OrderbookTableItem> {
  double _scale = 0.1;
  late Color _color;
  late TextStyle _style;
  late bool _isPreview;
  late bool _isTradeWithSelf;

  @override
  void initState() {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    _isPreview = widget.order.uuid == orderPreviewUuid;
    _isTradeWithSelf =
        widget.order.address ==
        coinsRepository.getCoin(widget.order.rel)?.address;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _scale = 1;
      });
    });

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    _style = typography.tabularAmountCompact.copyWith(fontSize: 12);
    _color = _isPreview
        ? colors.brand
        : widget.order.direction == OrderDirection.ask
        ? colors.danger
        : colors.success;
  }

  @override
  Widget build(BuildContext context) {
    if (_isPreview) {
      final motion = GleecMotion.of(context);
      return AnimatedScale(
        duration: motion.resolve(context, motion.standard),
        curve: motion.standardCurve,
        scale: _scale,
        child: _buildItem(),
      );
    }

    return _buildItem();
  }

  Widget _buildItem() {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: GleecGeometry.of(context).borderRadius12,
        onTap: widget.onClick == null || _isPreview
            ? null
            : () {
                widget.onClick!(widget.order);
              },
        child: Stack(
          alignment: Alignment.centerRight,
          clipBehavior: Clip.none,
          children: [
            _buildPointerIfNeeded(),
            _buildChartBar(),
            _buildTextData(),
          ],
        ),
      ),
    );
  }

  Widget _buildPointerIfNeeded() {
    if (_isTradeWithSelf) {
      return Positioned(
        left: 2,
        child: Icon(Icons.circle, size: 4, color: _color),
      );
    }

    if (_isPreview || widget.isSelected) {
      return Positioned(
        left: 0,
        child: Icon(Icons.forward, size: 8, color: _color),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildChartBar() {
    return FractionallySizedBox(
      widthFactor: widget.volumeFraction,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Container(color: _color.withValues(alpha: 0.1)),
      ),
    );
  }

  Widget _buildTextData() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Container(
        decoration: BoxDecoration(
          border: _isPreview
              ? Border(
                  bottom: BorderSide(
                    width: 0.5,
                    color: _color.withValues(alpha: 0.3),
                  ),
                  top: BorderSide(
                    width: 0.5,
                    color: _color.withValues(alpha: 0.3),
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            const SizedBox(width: 10),
            Expanded(
              child: AutoScrollText(
                text: widget.order.price.toDouble().toStringAsFixed(8),
                style: _style.copyWith(color: _color),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatAmt(widget.order.maxVolume.toDouble()),
              style: _style.copyWith(color: _isPreview ? _color : null),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
