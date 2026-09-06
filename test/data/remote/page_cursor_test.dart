import 'package:hearth/data/remote/page_cursor.dart';
import 'package:test/test.dart';

/// Reading every row of a table this device does not control (spec §7.1).
///
/// Two things go wrong with the obvious loop, and both are silent.
///
/// PostgREST caps a response at `max_rows` — a server setting this repo does
/// not track and cannot read. Code that stops when a page comes back shorter
/// than it asked for is guessing that number, and the old code did not
/// paginate at all: it asked once, got the cap, and treated it as the whole
/// answer.
///
/// And offset pagination reads "rows 500-999" of a result being written to.
/// A row updated mid-pull moves, everything after it shifts back one, and the
/// row on the boundary is stepped over — for good, because its own timestamp
/// never changed, so no later pull asks for it either.
void main() {
  /// A server holding [rows], handing back at most [cap] at a time.
  ///
  /// [cap] is deliberately not told to the caller — that is the point.
  ({Future<List<String>> Function(PageCursor?) page, int calls}) server(
    List<String> rows, {
    required int cap,
  }) {
    int calls = 0;
    Future<List<String>> page(PageCursor? after) async {
      calls++;
      final Iterable<String> remaining = after == null
          ? rows
          : rows.skipWhile((String r) => r.compareTo(after.values.single) <= 0);
      return remaining.take(cap).toList();
    }

    return (page: page, calls: calls);
  }

  PageCursor cursorOf(String row) => PageCursor(<String>[row]);

  test('reads past a cap it was never told about', () async {
    // The headline. 2,500 rows behind a 1,000-row cap: the old code took the
    // first thousand and moved its watermark past the rest, permanently.
    final List<String> rows = <String>[
      for (int i = 0; i < 2500; i++) i.toString().padLeft(4, '0'),
    ];

    final List<String> read = await readAllPages<String>(
      page: server(rows, cap: 1000).page,
      cursorOf: cursorOf,
    );

    expect(read, hasLength(2500));
    expect(read.first, '0000');
    expect(read.last, '2499');
  });

  test('and past a smaller one, without being told that either', () async {
    // The cap this repo cannot read might be 200. A loop that stops on a
    // short page would call 200 the end of a 500-row table.
    final List<String> rows = <String>[
      for (int i = 0; i < 500; i++) i.toString().padLeft(4, '0'),
    ];

    expect(
      await readAllPages<String>(
        page: server(rows, cap: 200).page,
        cursorOf: cursorOf,
      ),
      hasLength(500),
    );
  });

  test('an empty table is one call and no rows', () async {
    expect(
      await readAllPages<String>(
        page: server(<String>[], cap: 1000).page,
        cursorOf: cursorOf,
      ),
      isEmpty,
    );
  });

  test('a table that exactly fills one page still asks again', () async {
    // The boundary that makes "stop on a short page" wrong in the other
    // direction: 1,000 rows behind a 1,000 cap looks identical to 1,001.
    int calls = 0;
    final List<String> rows = <String>[
      for (int i = 0; i < 1000; i++) i.toString().padLeft(4, '0'),
    ];
    Future<List<String>> counted(PageCursor? after) async {
      calls++;
      return server(rows, cap: 1000).page(after);
    }

    expect(
      await readAllPages<String>(page: counted, cursorOf: cursorOf),
      hasLength(1000),
    );
    expect(calls, 2, reason: 'a full page must be followed by an empty one');
  });

  test(
    'a row written during the read is picked up, not stepped over',
    () async {
      // Keyset's whole reason. The row arrives sorted after everything, which
      // is where this loop is still heading — so it is read, and nothing that
      // was already read is disturbed.
      final List<String> rows = <String>[
        for (int i = 0; i < 300; i++) i.toString().padLeft(4, '0'),
      ];
      int calls = 0;
      Future<List<String>> growing(PageCursor? after) async {
        if (calls++ == 0) rows.add('9999');
        final Iterable<String> remaining = after == null
            ? rows
            : rows.skipWhile(
                (String r) => r.compareTo(after.values.single) <= 0,
              );
        return remaining.take(100).toList();
      }

      final List<String> read = await readAllPages<String>(
        page: growing,
        cursorOf: cursorOf,
      );

      expect(read, hasLength(301));
      expect(read.last, '9999');
    },
  );

  test('a cursor that cannot move is refused, not looped on', () async {
    // Only reachable if the sort key is not unique, which is why every
    // ordering ends in a key column. Looping would be the worse failure: the
    // same page for ever, on a phone, on battery.
    expect(
      readAllPages<String>(
        page: (PageCursor? after) async => <String>['same'],
        cursorOf: cursorOf,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('and so is a read that will not end', () async {
    int next = 0;
    expect(
      readAllPages<String>(
        page: (PageCursor? after) async => <String>['${next++}'],
        cursorOf: cursorOf,
        pageLimit: 5,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
