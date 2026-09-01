import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/foods/no_match_rule.dart';

/// Everything marked as needing no food, in one place (spec §5.3).
///
/// The fourth way in, and the only way back out. Marking salt happens where
/// salt is — in a recipe, on the row that was nagging — but a mistake made
/// there is otherwise undone only by finding the recipe that caused it, which
/// is no way to correct a household-wide rule.
///
/// Shows what Hearth ships knowing about as well as what has been added, since
/// "why is my cinnamon not being counted" has an answer and it should be
/// findable.
class SeasoningsScreen extends ConsumerWidget {
  const SeasoningsScreen({super.key});

  Future<void> _setMarked(
    WidgetRef ref,
    String wording, {
    required bool marked,
  }) async {
    final String household = ref.read(currentHouseholdIdProvider);
    final String id = const Uuid().v4();
    final DateTime now = DateTime.now();

    if (marked) {
      await ref
          .read(ingredientMatchStoreProvider)
          .rememberNoMatch(
            householdId: household,
            ingredientString: wording,
            id: id,
            updatedAt: now,
          );
    } else {
      // Recorded rather than forgotten: taking one of the built-ins back off
      // has to leave a trace, or the shipped list would simply reapply it.
      await ref
          .read(ingredientMatchStoreProvider)
          .rememberNeedsMatch(
            householdId: household,
            ingredientString: wording,
            id: id,
            updatedAt: now,
          );
    }
    ref.invalidate(noMatchRulesProvider);
    ref.invalidate(rememberedMatchesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HearthColors colors = context.colors;
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    final NoMatchRules rules =
        ref.watch(noMatchRulesProvider).value ?? NoMatchRules.none;

    // The household's own first — those are the decisions somebody made — then
    // the shipped list underneath.
    final List<String> yours = rules.marked.toList()..sort();
    final List<String> builtIn = NoMatchRules.seasoningKeys.toList()..sort();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Seasonings', style: context.text.sectionHeader),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(gutter),
          children: <Widget>[
            Text(
              'Ingredients marked as needing no food. They still appear in the '
              'recipe and still get cooked — they just stop being counted as a '
              'missing match, because there was never one to make.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: HearthSpacing.lg),
            if (yours.isNotEmpty) ...<Widget>[
              const _Heading(text: 'Yours'),
              for (final String wording in yours)
                _Row(
                  wording: wording,
                  marked: true,
                  builtIn: false,
                  onChanged: (bool on) => _setMarked(ref, wording, marked: on),
                ),
              const SizedBox(height: HearthSpacing.lg),
            ],
            const _Heading(text: 'Known to Hearth'),
            Padding(
              padding: const EdgeInsets.only(bottom: HearthSpacing.sm),
              child: Text(
                'Turn one off and it will ask to be matched like anything '
                'else.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
            ),
            for (final String wording in builtIn)
              if (!rules.marked.contains(wording))
                _Row(
                  wording: wording,
                  marked: !rules.unmarked.contains(wording),
                  builtIn: true,
                  onChanged: (bool on) => _setMarked(ref, wording, marked: on),
                ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: HearthSpacing.xs),
    child: Text(
      text,
      style: context.text.metadata.copyWith(color: context.colors.textMuted),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.wording,
    required this.marked,
    required this.builtIn,
    required this.onChanged,
  });

  final String wording;
  final bool marked;
  final bool builtIn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;

    return SwitchListTile.adaptive(
      value: marked,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(wording, style: context.text.body),
      subtitle: builtIn
          ? null
          : Text(
              'You marked this',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
    );
  }
}
