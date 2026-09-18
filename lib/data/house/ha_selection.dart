/// Which devices this phone shows, and in what order
/// (`docs/HOME_ASSISTANT_SPEC.md` §4.2, §5.3).
///
/// Three things this is, and one thing it is emphatically not.
///
/// It is **device-local**. §2 says selection and favourites do not sync in this
/// release: both people see the same real house, because the house is Home
/// Assistant's, but the choice of which corner of it to look at is this
/// installation's. So it goes through `PreferenceStore` — SQLite — rather than
/// anywhere shared.
///
/// It is **scoped and versioned**. Scoped to Hearth user, household and
/// connection for the same reason the credentials are (§5.2): signing in as
/// somebody else must not inherit their dashboard. Versioned because a stored
/// shape that cannot say what it is can only be guessed at later, and a wrong
/// guess about somebody's dashboard is a dashboard that rearranges itself.
///
/// It holds **references, never state**. §5.3: "do not store raw HA responses:
/// they can contain access tokens and signed media URLs." What is written here
/// is a list of entity ids somebody chose and the order they chose — no values,
/// no attributes, no names. Names and rooms belong to Home Assistant and are
/// read fresh.
///
/// And it is **not a security boundary** (§5.2). Home Assistant enforces what
/// the token's owner may do; this only decides what is drawn. Removing a device
/// from the dashboard does not remove anybody's access to it, and no screen may
/// imply otherwise.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../../domain/house/entity_id.dart';
import '../local/preference_store.dart';

/// One installation's dashboard choices.
@immutable
class HouseSelection {
  const HouseSelection({
    this.chosen = const <EntityId>[],
    this.favourites = const <EntityId>{},
  });

  /// Chosen devices, in the order somebody put them.
  ///
  /// A list rather than a set: §4.2 gives display order as a local choice, and
  /// a set would lose it on every read.
  final List<EntityId> chosen;

  /// Which of them come first. A subset of [chosen] — see [settled].
  final Set<EntityId> favourites;

  bool get isEmpty => chosen.isEmpty;

  /// The same selection with anything incoherent removed.
  ///
  /// Two ways a stored record can disagree with itself after an edit
  /// elsewhere: a favourite that is no longer chosen, and a duplicate. Both are
  /// resolved on read rather than trusted, because the file on disk was written
  /// by an older version of this code and will one day have been written by a
  /// newer one.
  HouseSelection get settled {
    final List<EntityId> unique = <EntityId>[];
    final Set<EntityId> seen = <EntityId>{};
    for (final EntityId id in chosen) {
      if (seen.add(id)) unique.add(id);
    }
    return HouseSelection(
      chosen: unique,
      favourites: favourites.where(seen.contains).toSet(),
    );
  }

  /// Adds [id] if it is not already chosen. Idempotent, so a double tap on a
  /// review screen cannot put a device on the list twice.
  HouseSelection with_(EntityId id) => chosen.contains(id)
      ? this
      : HouseSelection(
          chosen: <EntityId>[...chosen, id],
          favourites: favourites,
        );

  /// Removes [id], and stops it being a favourite.
  ///
  /// A favourite that is not chosen would come back the moment the device was
  /// re-added, which is a preference somebody expressed once and revoked.
  HouseSelection without(EntityId id) => HouseSelection(
    chosen: chosen.where((EntityId e) => e != id).toList(),
    favourites: favourites.where((EntityId e) => e != id).toSet(),
  );

  /// Marks or unmarks a favourite. Only something chosen can be one.
  HouseSelection favouring(EntityId id, {required bool yes}) {
    if (yes && !chosen.contains(id)) return this;
    return HouseSelection(
      chosen: chosen,
      favourites: yes
          ? <EntityId>{...favourites, id}
          : favourites.where((EntityId e) => e != id).toSet(),
    );
  }

  /// What is chosen but no longer offered by Home Assistant.
  ///
  /// §4.2: "A removed selected entity stays as a missing selection until the
  /// user removes or replaces it; no reassignment to a similarly named
  /// entity." So this reports rather than repairs — the dashboard shows a
  /// missing card, and a person decides what it should have been. Silently
  /// dropping it would hide that a door sensor stopped existing.
  List<EntityId> missingFrom(Set<EntityId> offered) =>
      chosen.where((EntityId id) => !offered.contains(id)).toList();

  @override
  bool operator ==(Object other) =>
      other is HouseSelection &&
      other.chosen.length == chosen.length &&
      other.favourites.length == favourites.length &&
      <int>[
        for (int i = 0; i < chosen.length; i++)
          if (other.chosen[i] != chosen[i]) i,
      ].isEmpty &&
      other.favourites.containsAll(favourites);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(chosen), Object.hashAllUnordered(favourites));
}

/// Reads and writes [HouseSelection] for one connection.
class HouseSelectionStore {
  const HouseSelectionStore(this._preferences);

  final PreferenceStore _preferences;

  /// The stored shape's version.
  ///
  /// Written with every record so a later version can migrate rather than
  /// guess. A record whose version this code does not know is treated as no
  /// record at all — see [read]. That loses a dashboard, which is recoverable
  /// in a minute; the alternative, interpreting an unknown shape, silently
  /// rearranges one, which is not.
  static const int version = 1;

  /// `house.ha.selection/<user>/<household>/<connection>`.
  ///
  /// Segmented so `deleteWithPrefix` can forget a whole user or household at
  /// once, matching what sign-out and a household change have to do (§5.2).
  static String keyFor({
    required String userId,
    required String householdId,
    required String connectionId,
  }) => '$_prefix$userId/$householdId/$connectionId';

  static String userPrefix(String userId) => '$_prefix$userId/';

  static String householdPrefix(String userId, String householdId) =>
      '$_prefix$userId/$householdId/';

  static const String _prefix = 'house.ha.selection/';

  Future<HouseSelection> read(String key) async {
    final String? raw = await _preferences.read(key);
    if (raw == null) return const HouseSelection();

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const HouseSelection();
      // An unknown version is not a record this code can read. Refusing it is
      // the honest answer; guessing is how a dashboard rearranges itself.
      if (decoded['v'] != version) return const HouseSelection();

      return HouseSelection(
        chosen: _ids(decoded['chosen']),
        favourites: _ids(decoded['favourites']).toSet(),
      ).settled;
    } on FormatException {
      // Corrupt. One lost dashboard beats a crash on every launch.
      return const HouseSelection();
    }
  }

  Future<void> write(String key, HouseSelection selection) {
    final HouseSelection clean = selection.settled;
    return _preferences.write(
      key,
      jsonEncode(<String, Object?>{
        'v': version,
        // Ids only. No names, no states, no attributes — §5.3 forbids storing
        // raw Home Assistant responses, and a name stored here would also go
        // stale the moment somebody renamed the thing in Home Assistant.
        'chosen': <String>[for (final EntityId id in clean.chosen) id.value],
        'favourites': <String>[
          for (final EntityId id in clean.favourites) id.value,
        ],
      }),
    );
  }

  /// Forgets every dashboard under [prefix].
  Future<void> forgetEverything(String prefix) {
    assert(
      prefix.startsWith(_prefix),
      'a sweep outside the selection prefix would take other settings with it',
    );
    return _preferences.deleteWithPrefix(prefix);
  }

  static List<EntityId> _ids(Object? value) => <EntityId>[
    if (value is List)
      for (final Object? entry in value)
        if (entry is String)
          if (EntityId.tryParse(entry) case final EntityId id) id,
  ];
}
