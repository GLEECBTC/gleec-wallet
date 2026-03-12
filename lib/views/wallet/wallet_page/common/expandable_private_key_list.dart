import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/wallet/coin_details/receive/qr_code_address.dart';

/// Widget for displaying private keys in an expandable list format.
///
/// **Security Architecture**: This widget implements the UI layer of the hybrid
/// security approach for private key handling:
/// - Receives private key data directly from parent widget (not from BLoC state)
/// - Visibility state is managed by [SecuritySettingsBloc] for consistency
/// - Private key data never passes through shared state
/// - Provides secure viewing, copying, and QR code functionality
///
/// **Security Features**:
/// - Private keys are hidden by default
/// - Toggle visibility controlled by BLoC state
/// - Individual and bulk copy functionality
/// - QR code display for easy import
/// - Proper cleanup when widget is disposed
class ExpandablePrivateKeyList extends StatelessWidget {
  /// Creates a new ExpandablePrivateKeyList widget.
  ///
  /// [privateKeys] Map of asset IDs to their corresponding private keys.
  /// **Security Note**: This data should be handled with extreme care and
  /// cleared from memory as soon as possible.
  const ExpandablePrivateKeyList({required this.privateKeys});

  /// Private keys organized by asset ID.
  ///
  /// **Security Note**: This data is intentionally passed directly to the UI
  /// rather than stored in BLoC state to minimize memory exposure and lifetime.
  final Map<AssetId, List<PrivateKey>> privateKeys;

  @override
  Widget build(BuildContext context) {
    if (privateKeys.isEmpty) {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.privateKeys.tr(),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: privateKeys.length,
          itemBuilder: (context, index) {
            final assetId = privateKeys.keys.elementAt(index);
            final keys = privateKeys[assetId]!;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PrivateKeyAssetSection(
                assetId: assetId,
                privateKeys: keys,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Widget for displaying private keys for a specific asset in an expandable section.
class PrivateKeyAssetSection extends StatefulWidget {
  const PrivateKeyAssetSection({
    super.key,
    required this.assetId,
    required this.privateKeys,
  });

  final AssetId assetId;
  final List<PrivateKey> privateKeys;

  @override
  State<PrivateKeyAssetSection> createState() => _PrivateKeyAssetSectionState();
}

class _PrivateKeyAssetSectionState extends State<PrivateKeyAssetSection> {
  bool _isExpanded = false;

  bool get _isSingleAddressAsset =>
      widget.assetId.subClass == CoinSubClass.tendermint ||
      widget.assetId.subClass == CoinSubClass.tendermintToken;

  List<PrivateKey> get _displayKeys => _isSingleAddressAsset
      ? widget.privateKeys.take(1).toList()
      : widget.privateKeys;

  @override
  void initState() {
    super.initState();
    // Attempt to restore state from PageStorage using a unique key
    _isExpanded =
        PageStorage.of(context).readState(
              context,
              identifier: 'private_key_${widget.assetId.id}_expanded',
            )
            as bool? ??
        false;
  }

  void _handleExpansionChanged(bool expanded) {
    setState(() {
      _isExpanded = expanded;
      // Save state to PageStorage using a unique key
      PageStorage.of(context).writeState(
        context,
        _isExpanded,
        identifier: 'private_key_${widget.assetId.id}_expanded',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Match the styling from ExpandableCoinListItem
    final horizontalPadding = 16.0;
    final verticalPadding = isMobile ? 16.0 : 22.0;

    return BlocSelector<SecuritySettingsBloc, SecuritySettingsState, bool>(
      selector: (state) => state.showPrivateKeys,
      builder: (context, showPrivateKeys) {
        final children = _displayKeys
            .map(
              (privateKey) => PrivateKeyListItem(
                assetId: widget.assetId,
                privateKey: privateKey,
                showPrivateKeys: showPrivateKeys,
              ),
            )
            .toList();

        return CollapsibleCard(
          key: PageStorageKey('private_key_${widget.assetId.id}'),
          borderRadius: BorderRadius.circular(12),
          headerPadding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          childrenMargin: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          childrenDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          initiallyExpanded: _isExpanded,
          onExpansionChanged: _handleExpansionChanged,
          expansionControlPosition: ExpansionControlPosition.leading,
          emptyChildrenBehavior: EmptyChildrenBehavior.disable,
          isDense: true,
          title: _buildTitle(context),
          maintainState: true,
          childrenDivider: const Divider(height: 1, indent: 16, endIndent: 16),
          children: children,
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context) {
    final theme = Theme.of(context);

    if (isMobile) {
      return _buildMobileTitle(context, theme);
    } else {
      return _buildDesktopTitle(context, theme);
    }
  }

  Widget _buildMobileTitle(BuildContext context, ThemeData theme) {
    final displayCount = _displayKeys.length;
    return Container(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use AssetIcon for visual consistency
          AssetIcon(widget.assetId, size: 34),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Asset name - using headlineMedium for bold 16px text
              Text(widget.assetId.id, style: theme.textTheme.headlineMedium),
              // Key count - using bodySmall for 12px secondary text
              Text(
                '$displayCount key${displayCount > 1 ? 's' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTitle(BuildContext context, ThemeData theme) {
    final displayCount = _displayKeys.length;
    return Container(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 180),
            child: Row(
              children: [
                AssetIcon(widget.assetId, size: 34),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.assetId.id,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        '$displayCount key${displayCount > 1 ? 's' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget for displaying a single private key with controls.
class PrivateKeyListItem extends StatefulWidget {
  const PrivateKeyListItem({
    super.key,
    required this.assetId,
    required this.privateKey,
    required this.showPrivateKeys,
  });

  final AssetId assetId;
  final PrivateKey privateKey;
  final bool showPrivateKeys;

  @override
  State<PrivateKeyListItem> createState() => _PrivateKeyListItemState();
}

class _PrivateKeyListItemState extends State<PrivateKeyListItem> {
  bool _isPrivateKeyVisible = false;

  @override
  void didUpdateWidget(covariant PrivateKeyListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showPrivateKeys && _isPrivateKeyVisible) {
      setState(() => _isPrivateKeyVisible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
    );
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      fontWeight: FontWeight.w600,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
    );
    final labelWidth = isMobile ? 90.0 : 120.0;
    final canReveal = widget.showPrivateKeys;
    final isVisible = canReveal && _isPrivateKeyVisible;
    final derivationPath = widget.privateKey.hdInfo?.derivationPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.key, size: 16, color: theme.colorScheme.primary),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (derivationPath != null) ...[
              _buildDetailRow(
                label: 'Path',
                labelStyle: labelStyle,
                labelWidth: labelWidth,
                value: AutoScrollText(
                  text: derivationPath,
                  style: subtitleStyle?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 6),
            ],
            _buildDetailRow(
              label: LocaleKeys.address.tr(),
              labelStyle: labelStyle,
              labelWidth: labelWidth,
              value: AutoScrollText(
                text: widget.privateKey.publicKeyAddress,
                style: subtitleStyle,
              ),
              actions: [
                IconButton(
                  iconSize: 16,
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    copyToClipBoard(
                      context,
                      widget.privateKey.publicKeyAddress,
                    );
                  },
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy address',
                ),
              ],
            ),
            if (widget.privateKey.publicKeySecp256k1.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildDetailRow(
                label: LocaleKeys.pubkey.tr(),
                labelStyle: labelStyle,
                labelWidth: labelWidth,
                value: AutoScrollText(
                  text: widget.privateKey.publicKeySecp256k1,
                  style: subtitleStyle?.copyWith(fontFamily: 'monospace'),
                ),
                actions: [
                  IconButton(
                    iconSize: 16,
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      copyToClipBoard(
                        context,
                        widget.privateKey.publicKeySecp256k1,
                      );
                    },
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy pubkey',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            _buildDetailRow(
              label: 'Private key',
              labelStyle: labelStyle,
              labelWidth: labelWidth,
              value: AutoScrollText(
                text: isVisible
                    ? widget.privateKey.privateKey
                    : '*' * widget.privateKey.privateKey.length,
                style: valueStyle,
              ),
              actions: [
                IconButton(
                  iconSize: 16,
                  icon: Icon(
                    isVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: canReveal
                      ? () {
                          setState(
                            () => _isPrivateKeyVisible = !_isPrivateKeyVisible,
                          );
                          if (_isPrivateKeyVisible) {
                            context.read<SecuritySettingsBloc>().add(
                              const ShowPrivateKeysCopiedEvent(),
                            );
                          }
                        }
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  iconSize: 16,
                  icon: const Icon(Icons.copy),
                  onPressed: canReveal
                      ? () {
                          copyToClipBoard(
                            context,
                            widget.privateKey.privateKey,
                          );
                          context.read<SecuritySettingsBloc>().add(
                            const ShowPrivateKeysCopiedEvent(),
                          );
                        }
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  iconSize: 16,
                  icon: const Icon(Icons.qr_code),
                  onPressed: canReveal ? _showQrDialog : null,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required TextStyle? labelStyle,
    required double labelWidth,
    required Widget value,
    List<Widget> actions = const [],
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(label, style: labelStyle),
        ),
        const SizedBox(width: 8),
        Expanded(child: value),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ],
    );
  }

  /// Shows a QR code dialog for the private key.
  ///
  /// **Security Note**: Only shown when private keys are visible and
  /// user explicitly requests it.
  void _showQrDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.assetId.id,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                  if (widget.privateKey.hdInfo?.derivationPath != null) ...[
                    Text(
                      'Path: ${widget.privateKey.hdInfo!.derivationPath}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                  QRCodeAddress(currentAddress: widget.privateKey.privateKey),
                  const SizedBox(height: 16),
                  SelectableText(
                    widget.privateKey.privateKey,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
