import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// unit tests: [testSorting]
int sortByDouble(double first, double second, SortDirection sortDirection) {
  if (sortDirection == SortDirection.none) return 0;

  // A comparator must return zero for equivalent values. Keep malformed or
  // overflowing values at the end in either direction instead of allowing
  // NaN arithmetic to violate Dart's sort contract.
  final firstIsValid = first.isFinite;
  final secondIsValid = second.isFinite;
  if (!firstIsValid || !secondIsValid) {
    if (firstIsValid) return -1;
    if (secondIsValid) return 1;
    return 0;
  }

  final comparison = first.compareTo(second);
  switch (sortDirection) {
    case SortDirection.increase:
      return comparison;
    case SortDirection.decrease:
      return -comparison;
    case SortDirection.none:
      return 0;
  }
}

int sortByOrderType(
  TradeSide first,
  TradeSide second,
  SortDirection sortDirection,
) {
  if (sortDirection == SortDirection.none) return 0;
  final comparison = first.index.compareTo(second.index);
  switch (sortDirection) {
    case SortDirection.increase:
      return comparison;
    case SortDirection.decrease:
      return -comparison;
    case SortDirection.none:
      return 0;
  }
}

int sortByBool(bool first, bool second, SortDirection sortDirection) {
  if (sortDirection == SortDirection.none || first == second) return 0;
  final comparison = (first ? 1 : 0).compareTo(second ? 1 : 0);
  switch (sortDirection) {
    case SortDirection.increase:
      return comparison;
    case SortDirection.decrease:
      return -comparison;
    case SortDirection.none:
      return 0;
  }
}
