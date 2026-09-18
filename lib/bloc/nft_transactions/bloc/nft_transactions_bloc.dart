import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/nft_transactions/bloc/nft_transactions_filters.dart';
import 'package:web_dex/bloc/nft_transactions/nft_txn_repository.dart';
import 'package:web_dex/bloc/nfts/nft_main_repo.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/rpc/nft_transaction/nft_transactions_response.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/shared/utils/utils.dart' as utils;
import 'package:web_dex/views/dex/dex_helpers.dart';

part 'nft_transactions_event.dart';
part 'nft_transactions_state.dart';

class NftTransactionsBloc extends Bloc<NftTxnEvent, NftTxnState> {
  NftTransactionsBloc({
    required NftTxnRepository nftTxnRepository,
    required KomodoDefiSdk kdfSdk,
    required CoinsRepo coinsRepository,
    required bool isLoggedIn,
    required NftsRepo nftsRepository,
  })  : _nftTxnRepository = nftTxnRepository,
        _coinsBloc = coinsRepository,
        _nftsRepository = nftsRepository,
        _isLoggedIn = isLoggedIn,
        super(NftTransactionsInitial()) {
    on<NftTxnReceiveEvent>(_onReceiveTransactions);
    on<NftTxReceiveDetailsEvent>(_onReceiveDetails);
    on<NftTxnEventSearchChanged>(_onSearchChanged);
    on<NftTxnEventStatusesChanged>(_onStatusesChanged);
    on<NftTxnEventBlockchainChanged>(_onBlockchainChanged);
    on<NftTxnEventStartDateChanged>(_startDateChanged);
    on<NftTxnEventEndDateChanged>(_endDateChanged);
    on<NftTxnClearFilters>(_cleanFilters);
    on<NftTxnEventFullFilterChanged>(_changeFullFilter);
    on<NftTxnEventNoLogin>(_noLogin);

    _authorizationSubscription = kdfSdk.auth.watchCurrentUser().listen((event) {
      final bool prevLoginState = _isLoggedIn;
      _isLoggedIn = event != null;

      if (_isLoggedIn && prevLoginState) {
        if (_isLoggedIn) {
          return add(const NftTxnReceiveEvent());
        } else {
          return add(const NftTxnEventNoLogin());
        }
      }
    });
  }

  final NftTxnRepository _nftTxnRepository;
  final NftsRepo _nftsRepository;
  final CoinsRepo _coinsBloc;
  final List<NftTransaction> _transactions = [];

  bool _isLoggedIn = false;
  late final StreamSubscription<KdfUser?> _authorizationSubscription;
  PersistentBottomSheetController? _bottomSheetController;
  set bottomSheetController(PersistentBottomSheetController controller) =>
      _bottomSheetController = controller;

  @override
  Future<void> close() async {
    await _authorizationSubscription.cancel();

    if (_bottomSheetController != null) {
      _bottomSheetController?.close();
      // Wait util bottom sheet will be closed
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return super.close();
  }

  Future<void> _onReceiveTransactions(
      NftTxnReceiveEvent event, Emitter<NftTxnState> emitter) async {
    if (!_isLoggedIn) return;
    emitter(state.copyWith(status: NftTxnStatus.loading));
    try {
      await _nftsRepository.updateNft(NftBlockchains.supportedValues);
      final response = await _nftTxnRepository.getNftTransactions();
      final transactions = response.transactions
        ..sort((a, b) => a.blockTimestamp.isAfter(b.blockTimestamp) ? -1 : 1);
      _transactions.clear();
      _transactions.addAll(transactions);
      for (var tx in _transactions) {
        if (tx.containsAdditionalInfo) {
          tx.setDetailsStatus(NftTxnDetailsStatus.success);
        }
      }

      return emitter(
        state.copyWith(
          filteredTransactions: _transactions,
          status: NftTxnStatus.success,
        ),
      );
    } on BaseError catch (e) {
      return emitter(
        state.copyWith(
          filteredTransactions: [],
          status: NftTxnStatus.failure,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      return emitter(
        state.copyWith(
          filteredTransactions: [],
          status: NftTxnStatus.failure,
        ),
      );
    }
  }

  Future<void> _onReceiveDetails(
      NftTxReceiveDetailsEvent event, Emitter<NftTxnState> emitter) async {
    if (!_isLoggedIn) return;

    final tx = event.tx;
    if (tx.containsAdditionalInfo) return;

    final int index = _transactions
        .indexWhere((element) => element.getTxKey() == event.tx.getTxKey());
    if (tx.detailsFetchStatus != NftTxnDetailsStatus.initial) return;

    try {
      final response =
          await _nftTxnRepository.getNftTxDetailsByHash(tx: event.tx);
      _transactions[index].confirmations = response.confirmations;
      _transactions[index].feeDetails = response.feeDetails;
      _transactions[index].setDetailsStatus(NftTxnDetailsStatus.success);
      // todo: @DmitriiP: improve because we use for loop [O(n)] each time
      return emitFilteredData(emitter);
    } on BaseError catch (e) {
      if (_transactions[index].detailsFetchStatus ==
          NftTxnDetailsStatus.initial) {
        final status =
            await retryReceiveDetails(index, event.tx.transactionHash);
        _transactions[index].setDetailsStatus(status);
        emitFilteredData(emitter);
      }
      return emitter(
        state.copyWith(errorMessage: e.message),
      );
    } catch (e) {
      if (_transactions[index].detailsFetchStatus ==
          NftTxnDetailsStatus.initial) {
        final status =
            await retryReceiveDetails(index, event.tx.transactionHash);
        _transactions[index].setDetailsStatus(status);
      }
      return emitFilteredData(emitter);
    }
  }

  Future<NftTxnDetailsStatus> retryReceiveDetails(
      int index, String txHash) async {
    int attempt = 5;
    NftTxnDetailsStatus status = NftTxnDetailsStatus.failure;
    while (attempt > 0) {
      try {
        await Future.delayed(const Duration(seconds: 2));
        attempt--;
        final response = await _nftTxnRepository.getNftTxDetailsByHash(
            tx: _transactions[index]);
        _transactions[index].confirmations = response.confirmations;
        _transactions[index].feeDetails = response.feeDetails;
        status = NftTxnDetailsStatus.success;
        attempt--;
        if (status == NftTxnDetailsStatus.success) break;
      } catch (_) {}
    }
    return status;
  }

  void _noLogin(NftTxnEventNoLogin event, Emitter<NftTxnState> emitter) {
    return emitter(
      state.copyWith(
        status: NftTxnStatus.noLogin,
      ),
    );
  }

  void _onSearchChanged(
      NftTxnEventSearchChanged event, Emitter<NftTxnState> emitter) {
    emitter(
      state.copyWith(
        filters: state.filters.copyWith(searchLine: event.searchLine),
      ),
    );
    emitFilteredData(emitter);
  }

  void _onStatusesChanged(
      NftTxnEventStatusesChanged event, Emitter<NftTxnState> emitter) {
    emitter(
      state.copyWith(
        filters: state.filters.copyWith(statuses: event.statuses),
      ),
    );
    emitFilteredData(emitter);
  }

  void _onBlockchainChanged(
      NftTxnEventBlockchainChanged event, Emitter<NftTxnState> emitter) {
    emitter(
      state.copyWith(
        filters: state.filters.copyWith(blockchain: event.blockchains),
      ),
    );
    emitFilteredData(emitter);
  }

  void _startDateChanged(
      NftTxnEventStartDateChanged event, Emitter<NftTxnState> emitter) {
    emitter(
      state.copyWith(
        filters: state.filters.copyWith(dateFrom: event.dateFrom),
      ),
    );
    emitFilteredData(emitter);
  }

  void _endDateChanged(
      NftTxnEventEndDateChanged event, Emitter<NftTxnState> emitter) {
    emitter(
      state.copyWith(
        filters: state.filters.copyWith(dateTo: event.dateTo),
      ),
    );
    emitFilteredData(emitter);
  }

  void _changeFullFilter(
      NftTxnEventFullFilterChanged event, Emitter<NftTxnState> emitter) {
    emitter(state.copyWith(filters: event.filter));

    emitFilteredData(emitter);
  }

  void emitFilteredData(Emitter<NftTxnState> emitter) {
    final filtered = _applyFilter();
    return emitter(
      state.copyWith(filteredTransactions: filtered),
    );
  }

  void _cleanFilters(NftTxnClearFilters event, Emitter<NftTxnState> emitter) {
    return emitter(
      state.copyWith(
        filters: const NftTransactionsFilter(),
        filteredTransactions: _transactions,
      ),
    );
  }

  List<NftTransaction> _applyFilter() {
    final filters = state.filters;
    final filteredTransactions = _transactions.where((transaction) {
      final includeTokenName = transaction.tokenName
              ?.toLowerCase()
              .contains(filters.searchLine.toLowerCase()) ??
          false;
      final includeTokenCollection = transaction.collectionName
              ?.toLowerCase()
              .contains(filters.searchLine.toLowerCase()) ??
          false;
      if (filters.searchLine.isNotEmpty &&
          !(includeTokenName || includeTokenCollection)) {
        return false;
      }
      if (filters.statuses.isNotEmpty &&
          !filters.statuses.contains(transaction.status)) {
        return false;
      }
      if (filters.blockchain.isNotEmpty &&
          !filters.blockchain.map((e) => e).contains(transaction.chain)) {
        return false;
      }
      if (filters.dateFrom != null &&
          transaction.blockTimestamp.isBefore(filters.dateFrom!)) {
        return false;
      }
      if (filters.dateTo != null &&
          transaction.blockTimestamp.isAfter(filters.dateTo!)) {
        return false;
      }
      return true;
    }).toList();
    return filteredTransactions;
  }

  Future<void> viewNftOnExplorer(NftTransaction transaction) async {
    final abbr = transaction.chain.coinAbbr();

    final activationErrors = await activateCoinIfNeeded(abbr, _coinsBloc);
    var coin = _coinsBloc.getCoin(abbr);
    if (coin != null) {
      if (activationErrors.isEmpty) {
        utils.viewHashOnExplorer(
          coin,
          transaction.transactionHash,
          utils.HashExplorerType.tx,
        );
      }
    }
  }
}
