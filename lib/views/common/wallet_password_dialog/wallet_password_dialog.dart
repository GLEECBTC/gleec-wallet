import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

// Shows wallet password dialog and
// returns password value or null (if wrong or cancelled)
Future<String?> walletPasswordDialog(
  BuildContext context, {
  Wallet? wallet,
  bool passwordOnly = false,
}) async {
  final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
  wallet ??= currentWallet;
  late PopupDispatcher popupManager;
  bool isOpen = false;
  String? password;

  void close() {
    popupManager.close();
    isOpen = false;
  }

  popupManager = PopupDispatcher(
    context: context,
    onDismiss: () => isOpen = false,
    popupContent: ScreenshotSensitive(
      child: PasswordDialogContent(
        wallet: wallet,
        passwordOnly: passwordOnly,
        onSuccess: (String pass) {
          password = pass;
          close();
        },
        onCancel: close,
      ),
    ),
  );

  isOpen = true;
  popupManager.show();

  while (isOpen) {
    await Future<dynamic>.delayed(const Duration(milliseconds: 100));
  }

  return password;
}

/// Shows password dialog with loading state for custom operations.
///
/// This dialog stays open during the operation process and shows
/// a loading indicator. The [onPasswordValidated] callback is called with
/// the validated password and should return a Future that completes when
/// the operation is finished.
Future<bool> walletPasswordDialogWithLoading(
  BuildContext context, {
  required Future<bool> Function(String password) onPasswordValidated,
  Wallet? wallet,
  String? loadingTitle,
  String? loadingMessage,
  String? operationFailedMessage,
  String passwordFieldKey = 'confirmation-showing-operation',
}) async {
  final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
  wallet ??= currentWallet;
  late PopupDispatcher popupManager;
  bool isOpen = false;
  bool operationSuccessful = false;

  void close() {
    popupManager.close();
    isOpen = false;
  }

  popupManager = PopupDispatcher(
    context: context,
    onDismiss: () => isOpen = false,
    popupContent: ScreenshotSensitive(
      child: PasswordDialogContentWithLoading(
        wallet: wallet,
        onPasswordValidated: onPasswordValidated,
        onComplete: (bool success) {
          operationSuccessful = success;
          close();
        },
        onCancel: close,
        loadingTitle: loadingTitle,
        loadingMessage: loadingMessage,
        operationFailedMessage: operationFailedMessage,
        passwordFieldKey: passwordFieldKey,
      ),
    ),
  );

  isOpen = true;
  popupManager.show();

  while (isOpen) {
    await Future<dynamic>.delayed(const Duration(milliseconds: 100));
  }

  return operationSuccessful;
}
