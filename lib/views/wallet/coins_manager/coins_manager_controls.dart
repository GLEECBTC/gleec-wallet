import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/custom_token_import/custom_token_import_button.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_filters_dropdown.dart';
import 'package:web_dex/views/wallet/coins_manager/coins_manager_select_all_button.dart';

class CoinsManagerFilters extends StatefulWidget {
  const CoinsManagerFilters({super.key, required this.isMobile});
  final bool isMobile;

  @override
  State<CoinsManagerFilters> createState() => _CoinsManagerFiltersState();
}

class _CoinsManagerFiltersState extends State<CoinsManagerFilters> {
  late final Debouncer _debouncer;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _debouncer = Debouncer(duration: const Duration(milliseconds: 100));
    _searchController = TextEditingController(
      text: context.read<CoinsManagerBloc>().state.searchPhrase,
    );
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return BlocListener<CoinsManagerBloc, CoinsManagerState>(
      listenWhen: (previous, current) =>
          previous.searchPhrase != current.searchPhrase,
      listener: (context, state) => _syncSearchField(state.searchPhrase),
      child: widget.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchField(context),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: isKeyboardVisible
                      ? const SizedBox.shrink()
                      : Column(
                          key: const Key('coins-manager-mobile-import'),
                          children: const [
                            SizedBox(height: 8),
                            CustomTokenImportButton(),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 20.0),
                        child: CoinsManagerSelectAllButton(),
                      ),
                      const Spacer(),
                      CoinsManagerFiltersDropdown(),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 240),
                      height: 45,
                      child: _buildSearchField(context),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 240),
                      height: 45,
                      child: const CustomTokenImportButton(),
                    ),
                    const Spacer(),
                    CoinsManagerFiltersDropdown(),
                  ],
                ),
              ],
            ),
    );
  }

  void _syncSearchField(String searchPhrase) {
    if (_searchController.text == searchPhrase) {
      return;
    }

    _searchController.value = _searchController.value.copyWith(
      text: searchPhrase,
      selection: TextSelection.collapsed(offset: searchPhrase.length),
      composing: TextRange.empty,
    );
  }

  void _dispatchSearchUpdate() {
    if (!mounted) {
      return;
    }

    context.read<CoinsManagerBloc>().add(
      CoinsManagerSearchUpdate(text: _searchController.text),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return UiTextFormField(
      key: const Key('coins-manager-search-field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      fillColor: widget.isMobile
          ? theme.custom.coinsManagerTheme.searchFieldMobileBackgroundColor
          : null,
      autocorrect: false,
      autofocus: true,
      textInputAction: TextInputAction.search,
      enableInteractiveSelection: true,
      prefixIcon: const Icon(Icons.search, size: 18),
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      hintText: LocaleKeys.searchAssets.tr(),
      hintTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      onChanged: (_) => _debouncer.run(_dispatchSearchUpdate),
    );
  }
}
