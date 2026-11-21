import 'package:flutter/material.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_by_file.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

class WalletImportWrapper extends StatefulWidget {
  const WalletImportWrapper({
    Key? key,
    required this.onImport,
    required this.onCancel,
    this.onImportTypeChanged,
  }) : super(key: key);

  final void Function({
    required String name,
    required String password,
    required WalletConfig walletConfig,
    required bool rememberMe,
  })
  onImport;
  final void Function() onCancel;

  /// Notifies the parent which import branch is on screen, so the onboarding
  /// funnel can distinguish a typed seed from an encrypted-file import.
  final void Function(WalletImportTypes)? onImportTypeChanged;

  @override
  State<WalletImportWrapper> createState() => _WalletImportWrapperState();
}

class _WalletImportWrapperState extends State<WalletImportWrapper> {
  WalletImportTypes _importType = WalletImportTypes.simple;
  WalletFileData? _fileData;

  @override
  Widget build(BuildContext context) {
    return _importType == WalletImportTypes.simple
        ? _buildSimpleImport()
        : _buildFileImport();
  }

  Widget _buildSimpleImport() {
    return WalletSimpleImport(
      onImport: widget.onImport,
      onUploadFiles: _onUploadFiles,
      onCancel: _onCancel,
    );
  }

  Widget _buildFileImport() {
    final WalletFileData? fileData = _fileData;
    assert(fileData != null);
    if (fileData != null) {
      return WalletImportByFile(
        fileData: fileData,
        onImport: widget.onImport,
        onCancel: _onCancel,
      );
    }
    return const SizedBox();
  }

  void _onUploadFiles({required String fileData, required String fileName}) {
    setState(() {
      _fileData = WalletFileData(content: fileData, name: fileName);
      _importType = WalletImportTypes.file;
    });
    widget.onImportTypeChanged?.call(WalletImportTypes.file);
  }

  void _onCancel() {
    if (_importType == WalletImportTypes.file) {
      setState(() {
        _importType = WalletImportTypes.simple;
        _fileData = null;
      });
      widget.onImportTypeChanged?.call(WalletImportTypes.simple);
      return;
    }

    widget.onCancel();
  }
}

enum WalletImportTypes { simple, file }
