import 'package:hearth/domain/models/food_profile.dart';
import 'package:test/test.dart';

/// What the generator is told, and how it is typed in (spec §5.4, §5.8).
void main() {
  group('what the generator sees', () {
    test('an empty profile says nothing rather than saying none', () {
      // An empty `allergies: []` reads as a considered "none". The difference
      // between that and "not asked" is not worth the model's attention.
      expect(FoodProfile.empty('user-1').toPrompt(), isEmpty);
    });

    test('constraints are named separately, because they are not the same', () {
      // An allergy is absolute; a dislike is steering the user can overrule.
      // Folding them together would lose exactly the thing that matters.
      final Map<String, Object?> prompt = const FoodProfile(
        userId: 'user-1',
        allergies: <String>['peanuts'],
        dislikes: <String>['mushrooms'],
      ).toPrompt();

      expect(prompt['allergies'], <String>['peanuts']);
      expect(prompt['dislikes'], <String>['mushrooms']);
    });

    test('a stated zero is not the same as no opinion', () {
      expect(
        const FoodProfile(
          userId: 'u',
          caloriesPerMeal: 0,
        ).toPrompt()['calories_per_meal'],
        0,
      );
      expect(
        const FoodProfile(userId: 'u')
            .toPrompt()
            .containsKey('calories_per_meal'),
        isFalse,
      );
    });
  });

  group('typing a list in', () {
    test('a comma-separated line becomes a list', () {
      expect(ProfileList.parse('peanuts, shellfish , sesame'), <String>[
        'peanuts',
        'shellfish',
        'sesame',
      ]);
    });

    test('empty and stray commas produce nothing', () {
      expect(ProfileList.parse(''), isEmpty);
      expect(ProfileList.parse('  ,  , '), isEmpty);
    });

    test('a list reads back the way it was typed', () {
      const List<String> values = <String>['peanuts', 'shellfish'];
      expect(ProfileList.parse(ProfileList.format(values)), values);
    });
  });
}
