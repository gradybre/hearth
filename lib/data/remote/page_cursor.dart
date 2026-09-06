import 'package:meta/meta.dart';

/// Where a page of rows stopped, so the next one can start after it.
///
/// A list of values, in the same order as the columns the query sorts by —
/// `[updated_at, id]` for most tables, the pair for the join tables that have
/// no timestamp at all.
@immutable
class PageCursor {
  const PageCursor(this.values);

  final List<String> values;

  @override
  bool operator ==(Object other) =>
      other is PageCursor &&
      other.values.length == values.length &&
      List<int>.generate(
        values.length,
        (int i) => i,
      ).every((int i) => other.values[i] == values[i]);

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => 'PageCursor(${values.join(', ')})';
}

/// Reads every row of a query, a page at a time.
///
/// **Keyset, not offset, and it stops on an empty page rather than on a short
/// one.** Both of those are load-bearing.
///
/// *Short pages.* PostgREST caps a response at `max_rows`, a server setting
/// this repo does not track and cannot read. Treating "fewer rows than I asked
/// for" as the end means guessing that number correctly; asking again until
/// the answer is nothing means never needing to know it. A cap of 200, 1,000
/// or anything else simply makes the pages smaller.
///
/// *Keyset.* Offset pagination reads `rows 500-999` of a result that is being
/// written to. A row updated during the pull moves, everything after its old
/// position shifts back by one, and the row that lands on the boundary is
/// stepped over — silently, and it will not be fetched again, because its own
/// timestamp never changed. Ordering by `(updated_at, id)` ascending and
/// asking for what sorts *after the last row seen* has no such window: a row
/// written mid-pull sorts to the end, where this loop is still heading.
///
/// The loop is here, rather than in the gateway, because this is the part
/// worth testing and a network is not.
Future<List<T>> readAllPages<T>({
  required Future<List<T>> Function(PageCursor? after) page,
  required PageCursor Function(T row) cursorOf,
  int pageLimit = 1000,
}) async {
  final List<T> all = <T>[];
  PageCursor? after;

  for (int pages = 0; pages < pageLimit; pages++) {
    final List<T> rows = await page(after);
    if (rows.isEmpty) return all;

    all.addAll(rows);
    final PageCursor next = cursorOf(rows.last);
    if (next == after) {
      // The cursor did not move, so asking again would return the same rows
      // for ever. Only reachable if the sort key is not unique — which is why
      // every ordering here ends in a key column.
      throw StateError(
        'Paging stalled at $next: the sort key is not unique, so the next '
        'page would repeat this one.',
      );
    }
    after = next;
  }

  // A ceiling on pages rather than on rows: at any sane page size this is
  // millions of records, and reaching it means the cursor is not advancing in
  // a way this loop can see. Refusing beats looping until the battery dies.
  throw StateError('Paging did not finish within $pageLimit pages.');
}
