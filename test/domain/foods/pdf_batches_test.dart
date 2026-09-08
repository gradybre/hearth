import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/domain/foods/pdf_batches.dart';

/// Reading a nutrition guide a batch at a time (spec §5.2).
///
/// The arithmetic behind what gets paid for and what gets claimed. Six pages
/// of eighteen is a fine offer; six pages of eighteen described as "the menu"
/// is a wrong answer with no way to notice, which is what the reader did
/// before there was anything here to ask.
void main() {
  group('which pages the next read asks for', () {
    test('the first six of a long document', () {
      expect(PdfBatches.next(pageCount: 18), <int>[1, 2, 3, 4, 5, 6]);
    });

    test('and all of a short one, without padding it', () {
      expect(PdfBatches.next(pageCount: 3), <int>[1, 2, 3]);
    });

    test('the next six once the first six are read', () {
      expect(
        PdfBatches.next(pageCount: 18, alreadyRead: <int>{1, 2, 3, 4, 5, 6}),
        <int>[7, 8, 9, 10, 11, 12],
      );
    });

    test('and what is left when that is fewer than six', () {
      expect(
        PdfBatches.next(pageCount: 8, alreadyRead: <int>{1, 2, 3, 4, 5, 6}),
        <int>[7, 8],
      );
    });

    test('nothing once the document is read', () {
      expect(
        PdfBatches.next(pageCount: 3, alreadyRead: <int>{1, 2, 3}),
        isEmpty,
        reason: 'an empty batch is what stops the offer being made again',
      );
    });

    test('a page that failed is offered again, not skipped for ever', () {
      // The read is recorded page by page rather than as a high-water mark,
      // so a page that would not render on the first pass is still unread and
      // comes back round. A count would have moved past it.
      expect(
        PdfBatches.next(
          pageCount: 12,
          alreadyRead: <int>{1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12},
        ),
        <int>[4],
      );
    });

    test('an empty document asks for nothing', () {
      expect(PdfBatches.next(pageCount: 0), isEmpty);
    });
  });

  group('how much is left', () {
    test('all of it before anything is read', () {
      expect(PdfBatches.remaining(pageCount: 18), 18);
    });

    test('and none of it after', () {
      expect(PdfBatches.remaining(pageCount: 2, alreadyRead: <int>{1, 2}), 0);
    });

    test('counting the gaps a failed page leaves', () {
      expect(
        PdfBatches.remaining(pageCount: 6, alreadyRead: <int>{1, 2, 4, 6}),
        2,
      );
    });
  });

  group('what it says it is reading', () {
    test('a run reads as a run', () {
      expect(
        PdfBatches.describe(<int>[7, 8, 9, 10, 11, 12], pageCount: 18),
        'Pages 7–12 of 18',
      );
    });

    test('one page is not a range', () {
      expect(PdfBatches.describe(<int>[3], pageCount: 18), 'Page 3 of 18');
    });

    test('and a batch with a hole in it says where the hole is', () {
      // The whole point. A batch that skipped page 9 described as "7–12"
      // would be the silence this exists to end: the number missing from the
      // menu is the one nobody knows to look for.
      expect(
        PdfBatches.describe(<int>[7, 8, 10, 11], pageCount: 18),
        'Pages 7, 8, 10 and 11 of 18',
      );
    });

    test('two pages that do not touch are a list, not a range', () {
      expect(
        PdfBatches.describe(<int>[2, 5], pageCount: 9),
        'Pages 2 and 5 of 9',
      );
    });

    test('order comes from the document, not from the caller', () {
      expect(
        PdfBatches.describe(<int>[3, 1, 2], pageCount: 4),
        'Pages 1–3 of 4',
      );
    });

    test('and nothing read says so rather than saying nothing', () {
      expect(PdfBatches.describe(<int>[], pageCount: 18), 'No pages of 18');
    });
  });
}
