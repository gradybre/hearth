import '../../domain/foods/restaurant_menu.dart';
import '../../domain/foods/usual_order_projection.dart';
import '../../domain/models/recipe.dart';
import '../../domain/text/text_normaliser.dart';
import '../../domain/units/quantity.dart';
import '../../domain/units/unit.dart';
import 'recipe_draft.dart';

/// The editor stores matches by ingredient name. It cannot preserve two
/// different matches (or a matched and deliberately unmatched line) under
/// the same name, so those choices need review before making a new draft.
List<String> usualOrderVariationConflicts({
  required UsualOrderProjection base,
  required List<MenuPick> picks,
}) {
  final Map<String, (String?, bool)> names = <String, (String?, bool)>{};
  final Map<String, String> conflicts = <String, String>{};
  final Map<String, MenuPick> remaining = <String, MenuPick>{
    for (final MenuPick pick in picks) pick.food.id: pick,
  };
  void remember(String name, String? foodId, bool noMatch) {
    final String key = normaliseKey(name);
    final (String?, bool) match = (foodId, noMatch);
    if (names.containsKey(key) && names[key] != match) {
      conflicts[key] = name;
    }
    names[key] = match;
  }

  for (final UsualOrderComponent component in base.components) {
    if (component.pick case final MenuPick original) {
      if (remaining.remove(original.food.id) == null) continue;
    }
    final RecipeIngredient ingredient = component.ingredient;
    remember(ingredient.name, ingredient.foodId, ingredient.needsNoMatch);
  }
  for (final MenuPick pick in remaining.values) {
    remember(pick.food.name, pick.food.id, false);
  }
  return conflicts.values.toList();
}

/// A variation is a new reusable recipe. Unrestored lines remain in the
/// review draft instead of disappearing from a partially restored order.
RecipeDraft usualOrderVariation({
  required UsualOrderProjection base,
  required List<MenuPick> picks,
}) {
  if (usualOrderVariationConflicts(base: base, picks: picks).isNotEmpty) {
    throw StateError(
      'Review conflicting ingredient names before creating a variation.',
    );
  }
  final Recipe recipe = base.recipe;
  final Map<String, UsualOrderComponent> components =
      <String, UsualOrderComponent>{
        for (final UsualOrderComponent component in base.components)
          component.ingredient.id: component,
      };
  final Map<String, MenuPick> remaining = <String, MenuPick>{
    for (final MenuPick pick in picks) pick.food.id: pick,
  };
  final Map<String, String> matches = <String, String>{};
  final Set<String> noMatch = <String>{};
  final List<DraftSection> sections = <DraftSection>[];

  for (final RecipeSection section in recipe.orderedSections) {
    final List<String> lines = <String>[];
    for (final RecipeIngredient ingredient in section.ingredients) {
      final UsualOrderComponent component = components[ingredient.id]!;
      Quantity? amount = ingredient.quantity;
      if (component.pick case final MenuPick original) {
        final MenuPick? selected = remaining.remove(original.food.id);
        if (selected == null) continue;
        // Untouched amounts keep their exact stored value and authored unit.
        // The portion count is a projection, not a replacement quantity.
        if (selected.count != original.count) amount = selected.quantity;
      }
      lines.add(
        _line(
          ingredient.name,
          amount,
          optional: ingredient.isOptional,
          prep: ingredient.prepNote,
        ),
      );
      if (ingredient.foodId case final String id) {
        matches[normaliseKey(ingredient.name)] = id;
      }
      if (ingredient.needsNoMatch) {
        noMatch.add(normaliseKey(ingredient.name));
      }
    }
    sections.add(
      DraftSection(
        name: section.isDefault && recipe.sections.length == 1
            ? ''
            : section.name,
        ingredientsText: lines.join('\n'),
        directionsText: section.orderedSteps
            .map((RecipeStep step) => '${step.stepNumber}. ${step.text}')
            .join('\n'),
      ),
    );
  }

  if (remaining.isNotEmpty) {
    final List<String> added = <String>[
      for (final MenuPick pick in remaining.values)
        _line(pick.food.name, pick.quantity),
    ];
    for (final MenuPick pick in remaining.values) {
      matches[normaliseKey(pick.food.name)] = pick.food.id;
    }
    if (sections.isEmpty) {
      sections.add(DraftSection(ingredientsText: added.join('\n')));
    } else {
      sections[0] = sections[0].copyWith(
        ingredientsText: <String>[
          if (sections[0].ingredientsText.isNotEmpty)
            sections[0].ingredientsText,
          ...added,
        ].join('\n'),
      );
    }
  }

  return RecipeDraft(
    title: '${recipe.title} (variation)',
    servings: recipe.servings,
    kind: RecipeKind.eatenOut,
    sections: sections,
    prepMinutes: recipe.prepTime?.inMinutes,
    cookMinutes: recipe.cookTime?.inMinutes,
    cuisine: recipe.cuisine,
    tags: recipe.tags,
    notes: recipe.notes,
    iconSvg: recipe.iconSvg,
    matches: matches,
    noMatch: noMatch,
  );
}

String _line(
  String name,
  Quantity? quantity, {
  bool optional = false,
  String? prep,
}) {
  String amount = '';
  if (quantity != null && quantity.canonicalAmount.isFinite) {
    Unit unit = quantity.preferredUnit ?? Units.canonicalFor(quantity.kind);
    double value = quantity.amountIn(unit);
    if (Quantity.of(value, unit).canonicalAmount != quantity.canonicalAmount) {
      unit = Units.canonicalFor(quantity.kind);
      value = quantity.amountIn(unit);
    }
    final String number = value.abs().toString().replaceFirst(
      RegExp(r'\.0$'),
      '',
    );
    amount =
        '${value < 0 ? '−' : ''}$number '
        '${unit.label.isEmpty ? 'ea' : unit.label} ';
  }
  return '$amount$name${optional ? ' (optional)' : ''}'
      '${prep == null || prep.trim().isEmpty ? '' : ', $prep'}';
}
