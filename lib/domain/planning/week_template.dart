import 'dart:convert';

import 'package:meta/meta.dart';

import 'meal_plan.dart';
import 'week.dart';

/// One meal in a saved week, placed by weekday rather than by date.
///
/// A weekday index, never a date: a template is a *shape* of a week, and a
/// date would pin it to the week it was saved from and make it useless on
/// every other one.
@immutable
class TemplateEntry {
  const TemplateEntry({
    required this.weekday,
    required this.slot,
    required this.refType,
    required this.refId,
    required this.servings,
  });

  /// 1 = Monday … 7 = Sunday, matching [DateTime.weekday] and the Monday-first
  /// week the rest of the app uses.
  final int weekday;

  final MealSlot slot;
  final PlanRefType refType;
  final String refId;
  final double servings;

  Map<String, Object?> toJson() => <String, Object?>{
    'weekday': weekday,
    'slot': slot.name,
    'ref_type': refType.name,
    'ref_id': refId,
    'servings': servings,
  };

  static TemplateEntry? fromJson(Map<String, Object?> json) {
    final int? weekday = switch (json['weekday']) {
      final num n => n.toInt(),
      _ => null,
    };
    final String refId = '${json['ref_id'] ?? ''}';
    if (weekday == null || weekday < 1 || weekday > 7 || refId.isEmpty) {
      return null;
    }

    final MealSlot? slot = MealSlot.values
        .where((MealSlot s) => s.name == json['slot'])
        .firstOrNull;
    final PlanRefType? refType = PlanRefType.values
        .where((PlanRefType t) => t.name == json['ref_type'])
        .firstOrNull;
    if (slot == null || refType == null) return null;

    return TemplateEntry(
      weekday: weekday,
      slot: slot,
      refType: refType,
      refId: refId,
      servings: switch (json['servings']) {
        final num n => n.toDouble(),
        _ => 1,
      },
    );
  }
}

/// A good week, saved so it can be had again (spec §5.6).
///
/// Private per user, like the plans it is made of (§5.1).
@immutable
class WeekTemplate {
  const WeekTemplate({
    required this.id,
    required this.name,
    required this.entries,
    this.updatedAt,
  });

  final String id;
  final String name;
  final List<TemplateEntry> entries;
  final DateTime? updatedAt;

  bool get isEmpty => entries.isEmpty;

  /// What a week's worth of plan entries reduces to.
  ///
  /// **Logged meals are included as intentions, not as history.** A week worth
  /// saving is usually one you have already eaten, so dropping the logged ones
  /// would save an empty template — and what carries across is the plan to eat
  /// the thing, never the record of having eaten it (§4).
  ///
  /// Deliberately keeps duplicates: two portions of the same lunch on the same
  /// day is a real thing to have planned.
  static List<TemplateEntry> from(Map<DateTime, List<MealPlanEntry>> byDay) {
    final List<TemplateEntry> out = <TemplateEntry>[];
    for (final MapEntry<DateTime, List<MealPlanEntry>> day in byDay.entries) {
      for (final MealPlanEntry entry in day.value) {
        out.add(
          TemplateEntry(
            weekday: dayKey(day.key).weekday,
            slot: entry.slot,
            refType: entry.refType,
            refId: entry.refId,
            servings: entry.servings,
          ),
        );
      }
    }
    out.sort((TemplateEntry a, TemplateEntry b) {
      final int byWeekday = a.weekday.compareTo(b.weekday);
      return byWeekday != 0 ? byWeekday : a.slot.index.compareTo(b.slot.index);
    });
    return out;
  }

  /// The dates each entry lands on when this template is applied to the week
  /// containing [anchor].
  ///
  /// Monday-first, via [startOfWeek], so a template saved from one week lands
  /// on the same weekdays of another.
  List<({DateTime date, TemplateEntry entry})> onWeekOf(DateTime anchor) {
    final DateTime monday = startOfWeek(anchor);
    return <({DateTime date, TemplateEntry entry})>[
      for (final TemplateEntry entry in entries)
        (date: monday.add(Duration(days: entry.weekday - 1)), entry: entry),
    ];
  }

  String encodeEntries() => jsonEncode(<Map<String, Object?>>[
    for (final TemplateEntry entry in entries) entry.toJson(),
  ]);

  /// Tolerant of nonsense: one unreadable entry loses that meal, not the whole
  /// template.
  static List<TemplateEntry> decodeEntries(String raw) {
    final Object? decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
    if (decoded is! List<Object?>) return const <TemplateEntry>[];
    return <TemplateEntry>[
      for (final Object? item in decoded)
        if (item is Map<String, Object?>)
          if (TemplateEntry.fromJson(item) case final TemplateEntry entry)
            entry,
    ];
  }
}
