import 'package:flutter/material.dart';

import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/adapters/label_reader.dart';
import 'food_draft.dart';

/// The recipe line a temporary food search or capture belongs to.
/// This is route context only; it is never a food field or a saved draft.
@immutable
class IngredientFoodCapture {
  const IngredientFoodCapture({
    required this.ingredientName,
    required this.authoredLine,
    this.recipeLineCount = 1,
  });

  final String ingredientName;
  final String authoredLine;
  final int recipeLineCount;
}

/// The existing food-route payload, accompanied by its ingredient context.
/// The router still accepts standalone [FoodDraft] and [LabelReading] extras.
@immutable
class IngredientFoodRouteExtra {
  const IngredientFoodRouteExtra({
    required this.capture,
    this.draft,
    this.label,
  });

  final IngredientFoodCapture capture;
  final FoodDraft? draft;
  final LabelReading? label;

  static FoodDraft? draftFrom(Object? extra) => switch (extra) {
    IngredientFoodRouteExtra(:final draft) => draft,
    FoodDraft() => extra,
    _ => null,
  };

  static LabelReading? labelFrom(Object? extra) => switch (extra) {
    IngredientFoodRouteExtra(:final label) => label,
    LabelReading() => extra,
    _ => null,
  };

  static Widget wrapRoute(Object? extra, Widget child) =>
      extra is IngredientFoodRouteExtra
      ? IngredientFoodCaptureScope(capture: extra.capture, child: child)
      : child;
}

class IngredientFoodCaptureScope extends InheritedWidget {
  const IngredientFoodCaptureScope({
    required this.capture,
    required super.child,
    super.key,
  });

  final IngredientFoodCapture capture;

  static IngredientFoodCapture? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<IngredientFoodCaptureScope>()
      ?.capture;

  /// Carry context through a nested capture, preserving legacy payloads for
  /// every standalone food route.
  static Object? routeExtra(
    BuildContext context, {
    FoodDraft? draft,
    LabelReading? label,
  }) {
    final capture = of(context);
    return capture == null
        ? draft ?? label
        : IngredientFoodRouteExtra(
            capture: capture,
            draft: draft,
            label: label,
          );
  }

  @override
  bool updateShouldNotify(IngredientFoodCaptureScope oldWidget) =>
      capture != oldWidget.capture;
}

/// Kept in scroll content so large text can wrap without stealing the whole
/// viewport from the editor or the actions below it.
class IngredientFoodBanner extends StatelessWidget {
  const IngredientFoodBanner({required this.capture, super.key});

  final IngredientFoodCapture capture;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(HearthSpacing.md),
    decoration: BoxDecoration(
      color: context.colors.surfaceSunken,
      border: Border.all(color: context.colors.outline),
      borderRadius: BorderRadius.circular(HearthRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          capture.recipeLineCount > 1
              ? 'Applies to ${capture.recipeLineCount} recipe lines'
              : 'For this ingredient',
          style: context.text.metadata,
        ),
        const SizedBox(height: HearthSpacing.xxs),
        Text(capture.authoredLine, style: context.text.ingredient),
      ],
    ),
  );
}
