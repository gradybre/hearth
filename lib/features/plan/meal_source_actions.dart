import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/models/recipe.dart';
import '../../domain/planning/meal_plan.dart';
import '../foods/food_detail_screen.dart';
import '../recipes/cook_along_screen.dart';

/// Day and Week open the same source while preserving a food's named serving.
void openMealSource(BuildContext context, MealPlanEntry entry) {
  switch (entry.refType) {
    case PlanRefType.recipe:
      context.push('/recipe/${entry.refId}');
    case PlanRefType.food:
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FoodDetailScreen(
            foodId: entry.refId,
            servingOptionId: entry.servingOptionId,
          ),
        ),
      );
  }
}

/// Read at the tap, so a stale row cannot cook a removed/reclassified recipe.
/// The full saved recipe is the cook snapshot, independent of personal portion.
void cookMealSource(BuildContext context, WidgetRef ref, MealPlanEntry entry) {
  if (entry.refType != PlanRefType.recipe) return;
  Recipe? saved;
  for (final Recipe current
      in ref.read(recipeLibraryProvider).value ?? const <Recipe>[]) {
    if (current.id == entry.refId && !current.isDeleted) {
      saved = current;
      break;
    }
  }
  if (saved == null) {
    _say(context, 'This recipe is no longer in your library.');
    return;
  }
  if (saved.isEatenOut) {
    _say(context, 'Restaurant meals do not have a cook-along.');
    return;
  }
  if (saved.allSteps.isEmpty) {
    _say(context, 'This recipe has no directions to cook along with yet.');
    return;
  }
  final Recipe snapshot = saved;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => CookAlongScreen(recipe: snapshot)),
  );
}

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
