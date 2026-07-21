import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/utils/utils.dart';

const int _maximumRecentSwapRecords = 1000;

class MyRecentSwapsResponse {
  const MyRecentSwapsResponse({required this.result});

  factory MyRecentSwapsResponse.fromJson(Map<String, dynamic> json) =>
      MyRecentSwapsResponse(
        result: MyRecentSwapsResponseResult.fromJson(
          Map<String, dynamic>.from(json['result'] as Map? ?? {}),
        ),
      );

  final MyRecentSwapsResponseResult result;

  Map<String, dynamic> get toJson => <String, dynamic>{'result': result.toJson};
}

class MyRecentSwapsResponseResult {
  const MyRecentSwapsResponseResult({
    required this.fromUuid,
    required this.limit,
    required this.skipped,
    required this.swaps,
    required this.total,
    required this.pageNumber,
    required this.foundRecords,
    required this.totalPages,
  });

  factory MyRecentSwapsResponseResult.fromJson(Map<String, dynamic> json) =>
      MyRecentSwapsResponseResult(
        fromUuid: json['from_uuid'] as String?,
        limit: assertInt(json['limit']) ?? 0,
        skipped: assertInt(json['skipped']) ?? 0,
        swaps: _parseRecentSwaps(json['swaps']),
        total: assertInt(json['total']) ?? 0,
        foundRecords: assertInt(json['found_records']) ?? 0,
        pageNumber: assertInt(json['page_number']) ?? 0,
        totalPages: assertInt(json['total_pages']) ?? 0,
      );

  final String? fromUuid;
  final int limit;
  final int skipped;
  final List<Swap> swaps;
  final int total;
  final int pageNumber;
  final int totalPages;
  final int foundRecords;

  Map<String, dynamic> get toJson => <String, dynamic>{
    'from_uuid': fromUuid,
    'limit': limit,
    'skipped': skipped,
    'swaps': List<dynamic>.from(
      swaps.map<Map<String, dynamic>>((Swap x) => x.toJson()),
    ),
    'total': total,
  };
}

List<Swap> _parseRecentSwaps(Object? value) {
  if (value is! List) return const [];
  final swaps = <Swap>[];
  for (final item in value.take(_maximumRecentSwapRecords)) {
    if (item is! Map) continue;
    try {
      swaps.add(Swap.fromJson(Map<String, dynamic>.from(item)));
    } catch (_) {
      // One corrupt daemon record must not take the wallet's entire history
      // offline. Invalid records are excluded and can be retried on refresh.
    }
  }
  return List<Swap>.unmodifiable(swaps);
}
