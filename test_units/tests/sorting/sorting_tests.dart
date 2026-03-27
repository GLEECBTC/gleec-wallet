import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:test/test.dart';
import 'package:web_dex/shared/utils/sorting.dart';

void testSorting() {
  test('Sort 2 numbers in desired direction', () {
    expect(sortByDouble(1, 2, SortDirection.decrease), 1);
  });
}
