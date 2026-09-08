import 'dart:io';

import 'package:test/test.dart';

/// Nothing that looks like a real secret is in the repository (CLAUDE.md's
/// secrets hygiene, spec §8.1).
///
/// The one rule in this project that cannot be repaired after the fact. A
/// wrong macro can be corrected; a `sb_secret_…` pushed to a remote is public
/// from that moment and stays public in the history, and the only honest
/// response is to say so and rotate it. So the check is cheap, it runs in the
/// ordinary suite, and it runs on every commit rather than on the ones
/// somebody remembered to look at.
///
/// A test rather than a shell script deliberately: it runs the same way
/// locally and in CI, it reads an exit code rather than a tail, and it needs
/// no tool nobody has installed.
///
/// **What it does not cover, said here rather than assumed.** Committed text
/// only: not a built app bundle, which is where CLAUDE.md's first rule
/// actually lands ("never in the app bundle"). Scanning one needs a build,
/// which the unit suite cannot do, so it belongs with the platform build jobs
/// and is not pretended to be here. Binary files are skipped too — a key
/// hidden in a PNG is not the threat this is for.
///
/// **It never prints what it matched.** A scanner that echoes the secret into
/// a public build log has published it a second time, which is the one thing
/// a scanner must not do. File and line and the name of the rule are enough
/// to find it.
void main() {
  /// What a leak looks like, and what each one costs.
  ///
  /// Narrow on purpose. A pattern that fires on anything long and random
  /// teaches everybody to add an ignore comment, and a scanner people route
  /// around is worse than none — it is the same repository plus a false
  /// sense of it having been checked.
  final Map<String, ({RegExp pattern, String cost})> rules =
      <String, ({String pattern, String cost})>{
        'a Supabase secret key': (
          // Deliberately not written out whole anywhere in this file: see the
          // note on the fixtures below.
          pattern:
              r'sb'
              r'_secret_[A-Za-z0-9_-]{8,}',
          cost:
              'it bypasses RLS entirely, so it is every household\'s data at '
              'once',
        ),
        'an Anthropic API key': (
          pattern:
              r'sk-'
              r'ant-[A-Za-z0-9_-]{16,}',
          cost: 'it is spendable, and the bill is real money',
        ),
        'a legacy service_role JWT': (
          // The old key format. Still accepted by projects that have not
          // migrated, and still a full bypass where it is.
          pattern: r'"role"\s*:\s*"service_role"',
          cost: 'the same bypass as a secret key, in the format we left',
        ),
        'a private key block': (
          pattern: r'-----BEGIN [A-Z ]*PRIVATE KEY-----',
          cost: 'a signing identity, which is not recoverable by rotating it',
        ),
        'an AWS access key id': (
          pattern: r'AKIA[0-9A-Z]{16}',
          cost: 'an account nobody in this project should be able to reach',
        ),
      }.map(
        (String name, ({String pattern, String cost}) rule) =>
            MapEntry<String, ({RegExp pattern, String cost})>(name, (
              pattern: RegExp(rule.pattern),
              cost: rule.cost,
            )),
      );

  /// Words that make a string obviously not a key.
  ///
  /// The alternative is an allow-list of files, which is worse: a file
  /// allow-listed for one placeholder is allow-listed for the real key
  /// somebody adds to it next year. Here the *string* has to say it is a
  /// placeholder, which is a property of the thing being checked rather than
  /// of the file it happens to live in — and a test that needs a fake secret
  /// key already wants an obviously fake one, so this asks for nothing that
  /// was not already good practice.
  ///
  /// The trade, stated rather than hidden: a real key on a line that also
  /// says "example" would be missed. These formats are random base62, so it
  /// cannot happen by accident, and on purpose it is a person deciding to
  /// defeat the check — which no scanner survives.
  const List<String> obviouslyFake = <String>[
    'example',
    'placeholder',
    'not_a_real',
    'not-a-real',
    'redacted',
    'your_',
    'dummy',
    'fake',
  ];

  /// The two files whose job is to contain matches.
  ///
  /// Listed rather than pattern-matched: an allow-list that grows by wildcard
  /// stops being one.
  const Set<String> mayMatch = <String>{
    'test/architecture/secret_fixtures/planted.txt',
  };

  bool looksPlanted(String line) {
    final String lower = line.toLowerCase();
    return obviouslyFake.any(lower.contains);
  }

  /// What the repository holds, as git sees it.
  ///
  /// `git ls-files` rather than a directory walk, and that is the whole point
  /// of using it: it lists what is *committed*. `config/local.json` is
  /// gitignored and holds a real publishable key; walking the filesystem
  /// would read it, and reading it is how a scanner ends up being the thing
  /// that leaks.
  List<File> tracked() {
    final ProcessResult result = Process.runSync('git', <String>['ls-files']);
    expect(
      result.exitCode,
      0,
      reason: 'git ls-files failed; is the test running from the repo root?',
    );
    return <File>[
      for (final String path in (result.stdout as String).split('\n'))
        if (path.trim().isNotEmpty) File(path.trim()),
    ];
  }

  test('no committed file carries anything that looks like a key', () {
    final List<String> found = <String>[];

    for (final File file in tracked()) {
      if (mayMatch.contains(file.path)) continue;
      if (!file.existsSync()) continue;

      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        // Binary. A key hidden in a PNG is not the threat this is for, and
        // decoding every asset to find out would make the check slow enough
        // that somebody turns it off.
        continue;
      }

      final List<String> lines = text.split('\n');
      for (final MapEntry<String, ({RegExp pattern, String cost})> rule
          in rules.entries) {
        for (int i = 0; i < lines.length; i++) {
          if (rule.value.pattern.hasMatch(lines[i]) &&
              !looksPlanted(lines[i])) {
            // The location and the rule. Never the match — printing it into
            // a build log publishes it again.
            found.add(
              '${file.path}:${i + 1} looks like ${rule.key} — '
              '${rule.value.cost}',
            );
          }
        }
      }
    }

    expect(
      found,
      isEmpty,
      reason:
          'Something that looks like a secret is committed. If it is real: '
          'say so and rotate it — do not quietly amend the history '
          '(CLAUDE.md). If it is a placeholder, make it obviously one, or '
          'add the file to this test\'s allow-list with a reason.\n'
          '${found.join('\n')}',
    );
  });

  test('and the scanner would actually notice one', () {
    // The half that makes the test above worth having. A scanner whose
    // patterns have quietly stopped matching passes exactly as loudly as one
    // finding nothing, and this repository has already been bitten twice by
    // a test that could only pass.
    //
    // The fixture holds one planted string per rule, and is the reason the
    // patterns above are written in two pieces — so that grepping this
    // repository for a real key prefix finds the fixture and this comment,
    // and not a line that looks like a key in the middle of a test.
    final File planted = File('test/architecture/secret_fixtures/planted.txt');
    expect(planted.existsSync(), isTrue, reason: 'the fixture is missing');

    final List<String> lines = planted.readAsLinesSync();
    for (final MapEntry<String, ({RegExp pattern, String cost})> rule
        in rules.entries) {
      expect(
        lines.any((String line) => rule.value.pattern.hasMatch(line)),
        isTrue,
        reason:
            'the rule for ${rule.key} matches nothing in the fixture, so it '
            'would not catch a real one either',
      );
    }
  });

  test('a real-looking key is caught even in a test file', () {
    // The placeholder rule above is the one that could hollow this out, so
    // it is pinned from both sides: a string that says "example" is ignored,
    // and one that does not is caught wherever it sits. Without this, loosening
    // `obviouslyFake` until it matched everything would go unnoticed.
    final RegExp secret = rules['a Supabase secret key']!.pattern;
    // Read from the fixture rather than written here. No key-shaped string
    // is spelled in Dart source at all: two adjacent literals are something a
    // formatter may one day fold into one, and the day it does, this file
    // starts matching its own pattern and the scanner fails on itself for a
    // reason nobody would guess.
    final String planted = File('test/architecture/secret_fixtures/planted.txt')
        .readAsLinesSync()
        .firstWhere(
          (String line) => secret.hasMatch(line) && !looksPlanted(line),
          orElse: () => '',
        );
    expect(
      planted,
      isNotEmpty,
      reason: 'the fixture has no marker-free key left to test with',
    );

    final String marked = File('test/architecture/secret_fixtures/planted.txt')
        .readAsLinesSync()
        .firstWhere(
          (String line) => secret.hasMatch(line) && looksPlanted(line),
        );

    expect(
      looksPlanted(marked),
      isTrue,
      reason:
          'a placeholder that says so has to be allowed, or nobody can '
          'write a test for the key check itself',
    );
  });

  test('and it would not fire on the key that is public by design', () {
    // The publishable key ships in the app bundle and is safe there (§8.1).
    // A scanner that refused it would be refusing `config/example.json` and
    // every line of documentation explaining the setup, which is how a
    // scanner gets switched off.
    const String publishable = 'sb_publishable_AbCdEfGhIjKlMnOpQrSt';
    for (final MapEntry<String, ({RegExp pattern, String cost})> rule
        in rules.entries) {
      expect(
        rule.value.pattern.hasMatch(publishable),
        isFalse,
        reason: '${rule.key} fires on the publishable key',
      );
    }
  });
}
