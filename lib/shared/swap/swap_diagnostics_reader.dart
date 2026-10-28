import 'dart:convert';

import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';

/// Reads support diagnostics without dropping exact funding or route evidence.
class SwapDiagnosticsReader {
  SwapDiagnosticsReader({
    required Mm2Api mm2,
    required RoutedSwapManager routed,
  }) : _mm2 = mm2,
       _routed = routed;

  final Mm2Api _mm2;
  final RoutedSwapManager _routed;

  Future<Map<String, Object?>> readBundle() async {
    final atomic = _atomicSwapData();
    final routed = _routedSwapData();
    return {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'atomic': await atomic,
      'routed': await routed,
    };
  }

  /// Preserves the legacy atomic list that can be pasted into Import Swaps.
  Future<String> atomicSwapText() async {
    try {
      final raw = await _mm2.getRawSwapData(MyRecentSwapsRequest());
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return jsonEncode(data['result']['swaps']);
    } on Object catch (error) {
      return error.toString();
    }
  }

  /// The raw `my_recent_swaps` answer, or a recorded reason it is absent, so
  /// the routed half still reaches support.
  Future<Object?> _atomicSwapData() async {
    try {
      return jsonDecode(await _mm2.getRawSwapData(MyRecentSwapsRequest()));
    } on Object catch (error) {
      return {'unavailable': error.toString()};
    }
  }

  /// Routed swaps for the export, or a recorded reason they are absent.
  ///
  /// A failure here must not lose the atomic half of the bundle, and it must
  /// not look like the user simply has no routed swaps — support would draw
  /// the wrong conclusion from an empty list.
  Future<Object> _routedSwapData() async {
    try {
      final entries = <RoutedSwapProgress>[];
      for (var page = 1; page <= 4; page++) {
        final result = await _routed.history(pageNumber: page, limit: 50);
        entries.addAll(result.entries);
        if (!result.hasMore) break;
      }
      return [
        for (final entry in entries)
          {
            'uuid': entry.uuid,
            'phase': entry.phase.name,
            'raw_state': entry.rawState,
            'stage': entry.bridgeStage?.name,
            'created_at': entry.createdAt?.toIso8601String(),
            'updated_at': entry.updatedAt?.toIso8601String(),
            'finished_at': entry.finishedAt?.toIso8601String(),
            'requested_from': entry.requested?.fromTicker,
            'requested_to': entry.requested?.toTicker,
            'requested_amount': entry.requested?.amount.toString(),
            'min_to_amount_accepted': entry.minToAmountAccepted?.toString(),
            'outcome': entry.receipt?.outcome.wire,
            'partial_reason': entry.receipt?.partialReason?.name,
            'received_amount': entry.receipt?.amount?.toString(),
            'received_token': entry.receipt?.tokenLabel,
            'provider_received_amount': entry.receipt?.reported?.amount
                .toString(),
            'provider_received_token': entry.receipt?.reported?.tokenLabel,
            'failure': entry.failure?.kind.name,
            'error_type': entry.failure?.errorType,
            'failure_message': entry.failure?.message,
            'shortfall': switch (entry.failure?.shortfall) {
              final shortfall? => {
                'coin': shortfall.ticker,
                'available': shortfall.available.toString(),
                'required': shortfall.required.toString(),
                'locked_by_swaps': shortfall.lockedBySwaps?.toString(),
              },
              null => null,
            },
            // These are distinct: history after a restart may no longer
            // retain the accepted in-memory offer. Never substitute execution.
            'accepted_route': entry.acceptedOffer?.route.toJson(),
            'executed_route': entry.executedOffer?.route.toJson(),
            'funds_movement': entry.failure?.fundsMovement.name,
            'provider_request_id': entry.failure?.providerRequestId,
            'approval_tx_hashes': entry.approvalTxHashes,
            'source_tx_hash': entry.sourceTxHash,
            'destination_tx_hash': entry.destinationTxHash,
            'explorer_url': entry.explorerUrl,
            'gas_spent': [
              for (final gas in entry.gasSpent)
                {
                  'coin': gas.ticker,
                  'amount': gas.amount.toString(),
                  'tx_hash': gas.txHash,
                },
            ],
          },
      ];
    } on Object catch (error) {
      return {'unavailable': error.toString()};
    }
  }
}
