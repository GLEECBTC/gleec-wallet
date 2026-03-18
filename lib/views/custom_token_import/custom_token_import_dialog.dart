import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_bloc.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_event.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class CustomTokenImportDialog extends StatefulWidget {
  const CustomTokenImportDialog({super.key});

  @override
  CustomTokenImportDialogState createState() => CustomTokenImportDialogState();
}

class CustomTokenImportDialogState extends State<CustomTokenImportDialog> {
  final PageController _pageController = PageController();

  Future<void> navigateToPage(int pageIndex) async {
    return _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    );
  }

  Future<void> goToNextPage() async {
    if (_pageController.page == null) return;

    await navigateToPage(_pageController.page!.toInt() + 1);
  }

  Future<void> goToPreviousPage() async {
    if (_pageController.page == null) return;

    await navigateToPage(_pageController.page!.toInt() - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 450,
        height: 358,
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ImportFormPage(onNextPage: goToNextPage),
            ImportSubmitPage(onPreviousPage: goToPreviousPage),
          ],
        ),
      ),
    );
  }
}

class BasePage extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onBackPressed;

  const BasePage({
    required this.title,
    required this.child,
    this.onBackPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onBackPressed != null)
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onBackPressed,
                  iconSize: 36,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              if (onBackPressed != null) const SizedBox(width: 16),
              Text(title, style: const TextStyle(fontSize: 18)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(child: child),
        ],
      ),
    );
  }
}

class ImportFormPage extends StatelessWidget {
  final VoidCallback onNextPage;

  const ImportFormPage({required this.onNextPage, super.key});

  @override
  Widget build(BuildContext context) {
    // keep controller outside of bloc consumer to prevent user inputs from
    // being hijacked by state updates
    final addressController = TextEditingController(text: '');
    return BlocConsumer<CustomTokenImportBloc, CustomTokenImportState>(
      listenWhen: (previous, current) =>
          previous.formStatus != current.formStatus,
      listener: (context, state) {
        if (state.formStatus == FormStatus.success ||
            state.formStatus == FormStatus.failure) {
          onNextPage();
        }
      },
      builder: (context, state) {
        final initialState = state.formStatus == FormStatus.initial;

        final isSubmitEnabled = initialState && state.address.isNotEmpty;

        return BasePage(
          title: LocaleKeys.importCustomToken.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade300.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade300),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        LocaleKeys.importTokenWarning.tr(),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<CoinSubClass>(
                initialValue: state.network,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: LocaleKeys.selectNetwork.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: state.supportedNetworks.map((CoinSubClass coinSubClass) {
                  return DropdownMenuItem<CoinSubClass>(
                    value: coinSubClass,
                    child: Text(coinSubClass.formatted),
                  );
                }).toList(),
                onChanged: !initialState
                    ? null
                    : (CoinSubClass? value) {
                        context.read<CustomTokenImportBloc>().add(
                          UpdateNetworkEvent(value),
                        );
                      },
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: addressController,
                enabled: initialState,
                onChanged: (value) {
                  context.read<CustomTokenImportBloc>().add(
                    UpdateAddressEvent(value),
                  );
                },
                decoration: InputDecoration(
                  labelText: LocaleKeys.tokenContractAddress.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              UiPrimaryButton(
                onPressed: isSubmitEnabled
                    ? () {
                        context.read<CustomTokenImportBloc>().add(
                          const SubmitFetchCustomTokenEvent(),
                        );
                      }
                    : null,
                child: state.formStatus == FormStatus.initial
                    ? Text(LocaleKeys.importToken.tr())
                    : const UiSpinner(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ImportSubmitPage extends StatelessWidget {
  final VoidCallback onPreviousPage;

  const ImportSubmitPage({required this.onPreviousPage, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CustomTokenImportBloc, CustomTokenImportState>(
      listenWhen: (previous, current) =>
          previous.importStatus != current.importStatus,
      listener: (context, state) {
        if (state.importStatus == FormStatus.success) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final newCoin = state.coin;
        final newCoinBalance = formatAmt(state.coinBalance.toDouble());
        final newCoinUsdBalance =
            '\$${formatAmt(state.coinBalanceUsd.toDouble())}';

        final isSubmitEnabled =
            state.importStatus != FormStatus.submitting &&
            state.importStatus != FormStatus.success &&
            newCoin != null;

        return BasePage(
          title: LocaleKeys.importCustomToken.tr(),
          onBackPressed: () {
            context.read<CustomTokenImportBloc>().add(
              const ResetFormStatusEvent(),
            );
            onPreviousPage();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: newCoin == null
                ? [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            '$assetsPath/logo/not_found.png',
                            height: 250,
                            filterQuality: FilterQuality.high,
                          ),
                          Text(LocaleKeys.tokenNotFound.tr()),
                        ],
                      ),
                    ),
                  ]
                : [
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AssetLogo.ofId(newCoin.id, size: 80),
                          const SizedBox(height: 12),
                          Text(
                            newCoin.id.id,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 32),
                          Text(
                            LocaleKeys.balance.tr(),
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$newCoinBalance ${newCoin.id.id} ($newCoinUsdBalance)',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    if (state.importErrorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          state.importErrorMessage,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    UiPrimaryButton(
                      onPressed: isSubmitEnabled
                          ? () {
                              context.read<CustomTokenImportBloc>().add(
                                const SubmitImportCustomTokenEvent(),
                              );
                            }
                          : null,
                      child:
                          state.importStatus == FormStatus.submitting ||
                              state.importStatus == FormStatus.success
                          ? const UiSpinner(color: Colors.white)
                          : Text(LocaleKeys.importToken.tr()),
                    ),
                  ],
          ),
        );
      },
    );
  }
}
