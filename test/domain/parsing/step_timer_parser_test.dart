import 'package:hearth/domain/parsing/step_timer_parser.dart';
import 'package:test/test.dart';

void main() {
  group('finds the timer stated in the step', () {
    test('minutes, in every spelling a recipe uses', () {
      expect(StepTimerParser.parse('Simmer for 20 minutes'), 1200);
      expect(StepTimerParser.parse('Simmer for 20 min'), 1200);
      expect(StepTimerParser.parse('Simmer for 20 mins'), 1200);
      expect(StepTimerParser.parse('Rest 1 minute'), 60);
    });

    test('hours, including the abbreviation', () {
      expect(StepTimerParser.parse('Cover and cook for approx. 3 hr.'), 10800);
      expect(StepTimerParser.parse('Braise for 2 hours'), 7200);
    });

    test('seconds', () {
      expect(StepTimerParser.parse('Blanch for 30 seconds'), 30);
    });

    test('a half hour written as a decimal', () {
      expect(StepTimerParser.parse('Chill for 1.5 hours'), 5400);
    });

    test('the number need not be separated from the unit', () {
      expect(StepTimerParser.parse('Bake 40min'), 2400);
    });
  });

  group('conservative — a wrong timer is worse than none', () {
    test('a step with no duration gets none', () {
      expect(StepTimerParser.parse('Season the ribs generously'), isNull);
      expect(StepTimerParser.parse('Serve over polenta.'), isNull);
    });

    test('an oven temperature is not a duration', () {
      expect(StepTimerParser.parse('Heat the oven to 350°F'), isNull);
    });

    test('a temperature followed by a time takes the time', () {
      expect(StepTimerParser.parse('Bake at 350°F for 40 minutes'), 2400);
    });

    test('the first duration wins; later ones are asides', () {
      // "turning at 20" is a note about the middle of the bake, not the bake.
      expect(
        StepTimerParser.parse('Bake for 40 minutes, turning at 20 minutes'),
        2400,
      );
    });

    test('a range takes its lower bound', () {
      // Called back to check beats called back to find it overdone.
      expect(StepTimerParser.parse('Roast for 20-25 minutes'), 1200);
      expect(StepTimerParser.parse('Roast for 20 to 25 minutes'), 1200);
      expect(StepTimerParser.parse('Roast for 20–25 min'), 1200);
    });

    test('a figure of speech is not a timer', () {
      expect(
        StepTimerParser.parse('This takes 2 seconds to throw together'),
        isNull,
      );
    });

    test('a cure or a marinade is described, not timed', () {
      expect(StepTimerParser.parse('Leave to cure for 48 hours'), isNull);
      expect(StepTimerParser.parse('Marinate overnight'), isNull);
    });

    test('a bare number is not a duration', () {
      expect(StepTimerParser.parse('Add 3 cloves of garlic'), isNull);
    });

    test('a word that merely starts with a unit is not one', () {
      // "3 minced" must not read as three minutes.
      expect(StepTimerParser.parse('Add 3 minced garlic cloves'), isNull);
      expect(StepTimerParser.parse('Stir in 2 hourglass-shaped pasta'), isNull);
    });
  });
}
