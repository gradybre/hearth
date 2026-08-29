import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../domain/models/food_profile.dart';

/// What you want out of a recipe (spec §5.4, §5.8).
///
/// Read by the generator so an allergy never has to be typed twice. Every
/// field is optional — §5.8 makes the questionnaire skippable, and an empty
/// profile is a perfectly good one that simply constrains nothing.
///
/// Deliberately not the 10–20 question onboarding pass §5.8 describes. This
/// covers what the generator actually reads; the questionnaire is onboarding
/// work and belongs with onboarding.
class FoodProfileScreen extends ConsumerStatefulWidget {
  const FoodProfileScreen({super.key});

  @override
  ConsumerState<FoodProfileScreen> createState() => _FoodProfileScreenState();
}

class _FoodProfileScreenState extends ConsumerState<FoodProfileScreen> {
  final TextEditingController _allergies = TextEditingController();
  final TextEditingController _dislikes = TextEditingController();
  final TextEditingController _preferences = TextEditingController();
  final TextEditingController _mealTypes = TextEditingController();
  final TextEditingController _calories = TextEditingController();
  final TextEditingController _protein = TextEditingController();

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _allergies,
      _dislikes,
      _preferences,
      _mealTypes,
      _calories,
      _protein,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fill(FoodProfile profile) {
    _allergies.text = ProfileList.format(profile.allergies);
    _dislikes.text = ProfileList.format(profile.dislikes);
    _preferences.text = ProfileList.format(profile.dietaryPreferences);
    _mealTypes.text = ProfileList.format(profile.preferredMealTypes);
    _calories.text = _number(profile.caloriesPerMeal);
    _protein.text = _number(profile.proteinPerMealG);
    _loaded = true;
  }

  static String _number(double? value) => switch (value) {
    null => '',
    final double v when v == v.roundToDouble() => v.round().toString(),
    final double v => v.toString(),
  };

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(foodProfileRepositoryProvider)
          .save(
            FoodProfile(
              userId: ref.read(currentUserIdProvider),
              allergies: ProfileList.parse(_allergies.text),
              dislikes: ProfileList.parse(_dislikes.text),
              dietaryPreferences: ProfileList.parse(_preferences.text),
              preferredMealTypes: ProfileList.parse(_mealTypes.text),
              caloriesPerMeal: double.tryParse(_calories.text.trim()),
              proteinPerMealG: double.tryParse(_protein.text.trim()),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final AsyncValue<FoodProfile> profile = ref.watch(foodProfileProvider);
    final double gutter = MediaQuery.sizeOf(context).width >= 840
        ? HearthSpacing.gutterExpanded
        : HearthSpacing.gutterCompact;

    if (!_loaded) {
      if (profile.value case final FoodProfile loaded) {
        _fill(loaded);
      } else if (profile.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Your food profile', style: context.text.sectionHeader),
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: HearthSpacing.sm),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(gutter),
          children: <Widget>[
            Text(
              'Hearth reads this when it writes you a recipe, so you never '
              'have to say it twice. All of it is optional.',
              style: context.text.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: HearthSpacing.xl),
            // Allergies lead, and are described as absolute, because that is
            // how they are treated (§5.4). Burying them among preferences
            // would misrepresent what the generator does with them.
            _ListField(
              controller: _allergies,
              label: 'Allergies',
              hint: 'peanuts, shellfish',
              help: 'Never used, whatever a recipe is asked for.',
            ),
            const SizedBox(height: HearthSpacing.lg),
            _ListField(
              controller: _dislikes,
              label: 'Dislikes',
              hint: 'mushrooms, blue cheese',
              help: 'Avoided, unless you ask for them anyway.',
            ),
            const SizedBox(height: HearthSpacing.lg),
            _ListField(
              controller: _preferences,
              label: 'How you eat',
              hint: 'high protein, vegetarian',
            ),
            const SizedBox(height: HearthSpacing.lg),
            _ListField(
              controller: _mealTypes,
              label: 'Meals you reach for',
              hint: 'bowls, soups, traybakes',
            ),
            const SizedBox(height: HearthSpacing.xl),
            Text('Roughly per meal', style: context.text.sectionHeader),
            const SizedBox(height: HearthSpacing.xs),
            Text(
              'A steer, not a target — your weekly targets are set in Plan.',
              style: context.text.metadata.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: HearthSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: _NumberField(controller: _calories, label: 'Calories'),
                ),
                const SizedBox(width: HearthSpacing.md),
                Expanded(
                  child: _NumberField(
                    controller: _protein,
                    label: 'Protein (g)',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A comma-separated list, because three things is a sentence.
class _ListField extends StatelessWidget {
  const _ListField({
    required this.controller,
    required this.label,
    required this.hint,
    this.help,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: context.text.metadata.copyWith(color: colors.textSecondary),
        ),
        if (help != null)
          Text(
            help!,
            style: context.text.metadata.copyWith(color: colors.textMuted),
          ),
        const SizedBox(height: HearthSpacing.xs),
        TextField(
          controller: controller,
          style: context.text.body,
          decoration: InputDecoration(hintText: hint, isDense: false),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: context.text.metadata.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      const SizedBox(height: HearthSpacing.xs),
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: context.text.body,
        decoration: const InputDecoration(hintText: '—', isDense: false),
      ),
    ],
  );
}
