import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/utils/utils.dart';

class MyRecentSwapsResponse {
  MyRecentSwapsResponse({required this.result});

  factory MyRecentSwapsResponse.fromJson(Map<String, dynamic> json) =>
      MyRecentSwapsResponse(
        result: MyRecentSwapsResponseResult.fromJson(
          Map<String, dynamic>.from(json['result'] as Map? ?? {}),
        ),
      );

  MyRecentSwapsResponseResult result;

  Map<String, dynamic> get toJson => <String, dynamic>{'result': result.toJson};
}

class MyRecentSwapsResponseResult {
  MyRecentSwapsResponseResult({
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
        swaps: List<Swap>.from(
          (json['swaps'] as List? ?? <Swap>[])
              .where((dynamic x) => x != null)
              .map(
                (dynamic x) => Swap.fromJson(x as Map<String, dynamic>? ?? {}),
              ),
        ),
        total: assertInt(json['total']) ?? 0,
        foundRecords: assertInt(json['found_records']) ?? 0,
        pageNumber: assertInt(json['page_number']) ?? 0,
        totalPages: assertInt(json['total_pages']) ?? 0,
      );

  String? fromUuid;
  int limit;
  int skipped;
  List<Swap> swaps;
  int total;
  int pageNumber;
  int totalPages;
  int foundRecords;

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
