/// The drawings Hearth makes of itself (spec §6.1, and the November 2026
/// templates).
///
/// **Hand-authored paths, not pictures.** Three ways to get these were put to
/// Brendan and he chose this one. A raster would need a source he was happy
/// with, a licence note and a second file for dark mode; these are a few
/// hundred bytes of path data that take their colour from the theme, stay
/// crisp at any size, and can be read and changed in the same editor as the
/// code around them.
///
/// They go through [SketchIcon] like a recipe's own sketch: the same
/// whitelist, the same painter, the same discarding of whatever colours the
/// markup names. That is not ceremony — it is what keeps one drawing from
/// being a special case with its own renderer, and a test holds every mark
/// here to it.
///
/// Drawn on a 64-point grid with a 2.4 stroke, which at the sizes these are
/// used reads as a pen line rather than a rule. The templates' art is softer
/// and more detailed than this; what is here is the shape of it, in the one
/// medium that is correct in both themes.
library;

/// Hearth's own mark: a lidded casserole, seen from the side.
///
/// One drawing at two sizes — small beside the wordmark in the sidebar,
/// large above the home screen's hero. The lid is a separate stroke from the
/// rim so the pot reads as closed rather than as a bowl with a line over it.
///
/// **No herbs.** The templates set a sprig beside the pot and it does not
/// survive the translation: in seven pen strokes at this weight it reads as
/// a scribble, and two attempts at it looked like an insect rather than
/// thyme. The pot is the subject and the garnish is what the rendered art
/// could afford.
const String kPotMark =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<g fill="none" stroke="currentColor" stroke-width="2.4">'
    '<path d="M13 31 L13 45 Q13 53 21 53 L43 53 Q51 53 51 45 L51 31"/>'
    '<path d="M9 31 L55 31"/>'
    '<path d="M15 31 Q32 18 49 31"/>'
    '<path d="M32 18 L32 14.6"/>'
    '<circle cx="32" cy="12" r="2.6"/>'
    '<path d="M13 35 Q6 35 6 39.5 Q6 44 13 44"/>'
    '<path d="M51 35 Q58 35 58 39.5 Q58 44 51 44"/>'
    '</g></svg>';

/// A cottage with smoke from the chimney, for the House room.
///
/// The one room that is about the building rather than about what happens
/// inside it, which is why it is the one the templates draw a house for.
const String kCottageMark =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<g fill="none" stroke="currentColor" stroke-width="2.4">'
    '<path d="M14 54 L14 33"/>'
    '<path d="M50 54 L50 33"/>'
    '<path d="M9 34 L32 17 L55 34"/>'
    '<path d="M7 54 L57 54"/>'
    '<path d="M27 54 L27 42 L37 42 L37 54"/>'
    '<rect x="18" y="38" width="7" height="7"/>'
    '<path d="M42 25 L42 17 L46 17 L46 27.5"/>'
    '<path d="M44 13.5 Q40 10.5 44 7.5 Q48 4.5 44 1.5"/>'
    '</g></svg>';

/// Every mark in this file, for the test that holds them to the whitelist.
const List<({String name, String svg})> kHearthMarks =
    <({String name, String svg})>[
      (name: 'kPotMark', svg: kPotMark),
      (name: 'kCottageMark', svg: kCottageMark),
    ];
