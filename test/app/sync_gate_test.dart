import 'package:hearth/app/sync_gate.dart';
import 'package:test/test.dart';

/// A sync asked for during a sync (spec §7.1, B01).
///
/// The old guard was a bare `if (_running) return;`, which dropped the
/// request. A write made while a pass was in flight then waited for something
/// else to trigger one — and the obvious something is another write, which
/// the user may not make for hours.
void main() {
  late SyncGate gate;

  setUp(() => gate = SyncGate());

  test('the first caller runs', () {
    expect(gate.start(), isTrue);
    expect(gate.isRunning, isTrue);
  });

  test('a second caller does not, but is remembered', () {
    gate.start();

    expect(gate.start(), isFalse, reason: 'two passes must not overlap');
    expect(gate.finish(), isTrue, reason: 'the request was dropped');
  });

  test('a burst during one pass earns exactly one rerun', () {
    // Saving a recipe queues several rows and each one nudges a sync. One
    // rerun is the point; several would be worse than the bug.
    gate.start();
    for (int i = 0; i < 20; i++) {
      gate.start();
    }

    expect(gate.finish(), isTrue);

    gate.start();
    expect(
      gate.finish(),
      isFalse,
      reason: 'the rerun re-earned itself, which never ends',
    );
  });

  test('an uneventful pass owes nothing', () {
    gate.start();

    expect(gate.finish(), isFalse);
    expect(gate.isRunning, isFalse);
  });

  test('and the gate reopens afterwards', () {
    gate.start();
    gate.finish();

    expect(gate.start(), isTrue);
  });

  test('a pass that ends badly still reopens it', () {
    // `finish` runs in a `finally`. A gate left closed by a thrown pass would
    // stop this device syncing until the app was restarted.
    gate.start();
    try {
      throw Exception('the pass blew up');
    } on Exception {
      gate.finish();
    }

    expect(gate.start(), isTrue);
  });
}
