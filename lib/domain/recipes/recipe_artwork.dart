/// The pictures a recipe can fall back to when it has none of its own
/// (spec §5.2, §6.1).
///
/// **Archetypes, not portraits.** The November 2026 templates draw a jar, a
/// bowl and a lasagne; none of them is a picture of a particular recipe, and
/// at the 36 to 48 points a library row gives a thumbnail, nothing more
/// specific would be legible anyway. So the library is a fixed set of
/// drawings of *kinds* of food, matched to a recipe by its words.
///
/// A fixed set is what makes the good version affordable. Art generated per
/// recipe costs money on every recipe for ever, needs a review step before
/// it lands in somebody's library, and has to be synced to the other phone;
/// a set that ships with the app is drawn once, reviewed once, licensed
/// once, and works with the aeroplane mode on.
///
/// Pure Dart, and deliberately: the matching is the part that can be wrong,
/// it is the cheapest test surface in the app (spec §9.1), and every
/// interesting case — "chicken pot pie stew", "eggs benedict", "pear and
/// almond tart" — is a string.
library;

import 'package:meta/meta.dart';

/// One drawing, and the words that should find it.
@immutable
class RecipeArtwork {
  const RecipeArtwork(this.id, this.keywords);

  /// Stable, lower-case, hyphenated. It is the asset's file name and the
  /// name the artwork brief lists, so renaming one means renaming a file.
  final String id;

  /// What a recipe might say to mean this drawing.
  ///
  /// Matched on whole words, so "pear" cannot be found inside "appear" and
  /// "ham" cannot be found inside "hammer". A phrase matches a run of
  /// consecutive words.
  final List<String> keywords;
}

/// Splits a line of human text into the words the matcher compares.
///
/// Lower-cased, letters and digits only, so punctuation, accents' casing
/// and the em dashes a recipe title collects are all out of the way before
/// anything is compared.
List<String> recipeWords(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((String w) => w.isNotEmpty)
    .toList(growable: false);

/// Which drawing a recipe should wear, or null when nothing fits.
///
/// Null is a real answer and the common one early on: a household's first
/// recipes are whatever they cooked last week, and a wrong picture is worse
/// than none. The caller falls through to the recipe's own sketch.
///
/// **The title decides first.** "Teriyaki Beef Rice Bowls" filed under
/// "meal prep" is a rice bowl, not a lunchbox — but "meal prep" is two
/// words and "rice" is one, so ranking by phrase length alone handed it to
/// the lunchbox. A tag says how a dish was filed and sometimes how it is
/// cooked; the title says what it is. So a drawing named in the title beats
/// one named only in a tag or a cuisine, however long the phrase.
///
/// **Then the longest phrase, and only then the most hits.** "Sweet potato
/// mash" says potato twice over — "potato" and "mash" both point at the
/// potato drawing — and says "sweet potato" once; counting hits gives the
/// wrong one. A two-word phrase is a more specific claim than two one-word
/// hits.
///
/// Registry order breaks what is still level, which makes the answer stable
/// rather than merely plausible.
///
/// A keyword also matches its own plural, so "tacos" finds the taco and
/// "brownies" the brownie. One direction only — the keyword gains an s, the
/// title never loses one — because stripping an s turns hummus into hummu
/// and asparagus into asparagu.
String? pickRecipeArtwork({
  required String title,
  Iterable<String> tags = const <String>[],
  String? cuisine,
}) {
  final List<String> titleWords = recipeWords(title);
  final List<String> otherWords = <String>[
    for (final String tag in tags) ...recipeWords(tag),
    if (cuisine != null) ...recipeWords(cuisine),
  ];

  String? best;
  bool bestTitled = false;
  int bestScore = 0;
  int bestLength = 0;

  for (final RecipeArtwork art in kRecipeArtwork) {
    int score = 0;
    int longest = 0;
    bool titled = false;
    for (final String keyword in art.keywords) {
      final List<String> phrase = recipeWords(keyword);
      if (phrase.isEmpty) continue;
      final bool inTitle = _contains(titleWords, phrase);
      final bool inOther = _contains(otherWords, phrase);
      if (!inTitle && !inOther) continue;
      score += inTitle ? 3 : 2;
      if (inTitle) titled = true;
      if (phrase.length > longest) longest = phrase.length;
    }
    if (score == 0) continue;
    final bool better =
        (titled && !bestTitled) ||
        (titled == bestTitled &&
            (longest > bestLength ||
                (longest == bestLength && score > bestScore)));
    if (better) {
      best = art.id;
      bestTitled = titled;
      bestScore = score;
      bestLength = longest;
    }
  }
  return best;
}

bool _contains(List<String> words, List<String> phrase) {
  if (phrase.length > words.length) return false;
  for (int i = 0; i + phrase.length <= words.length; i++) {
    bool all = true;
    for (int j = 0; j < phrase.length; j++) {
      if (!_sameWord(words[i + j], phrase[j])) {
        all = false;
        break;
      }
    }
    if (all) return true;
  }
  return false;
}

/// Whether a word from the recipe means the keyword.
///
/// The keyword may gain an s or an es; the recipe's word is never shortened.
/// Going the other way would make hummus a hummu and asparagus an asparagu,
/// and both would then match nothing.
bool _sameWord(String word, String keyword) =>
    word == keyword || word == '${keyword}s' || word == '${keyword}es';

RecipeArtwork _a(String id, String keywords) => RecipeArtwork(
  id,
  keywords.split(',').map((String k) => k.trim()).toList(growable: false),
);

/// Every drawing the app knows how to ask for.
///
/// Ordered most specific first within each group, because registry order is
/// the last tie-break: a dish that reads as both a pie and a stew should get
/// the pie, and a dish that reads as both a curry and a bowl should get the
/// curry.
///
/// Adding one is a line here and a file in `assets/art`. A drawing that has
/// not been made yet simply does not appear — the widget falls through to
/// the recipe's own sketch — so the list can run ahead of the artist.
final List<RecipeArtwork> kRecipeArtwork = <RecipeArtwork>[
  // ---- Composed dishes, which are what most titles name -----------------
  _a('pot-pie', 'pot pie, chicken pie, steak pie, shepherds pie, cottage pie'),
  _a('stew-pot', 'stew, casserole, braise, braised, pot roast, hotpot, ragout'),
  _a('chilli-bowl', 'chilli, chili, con carne'),
  _a(
    'curry-bowl',
    'curry, korma, tikka masala, vindaloo, rogan josh, dhansak, dal, dahl',
  ),
  _a('tagine', 'tagine, tajine'),
  _a('ramen-bowl', 'ramen, tonkotsu'),
  _a('pho-bowl', 'pho'),
  _a(
    'noodle-bowl',
    'noodles, noodle, lo mein, chow mein, pad thai, udon, soba',
  ),
  _a(
    'pasta-plate',
    'pasta, spaghetti, linguine, penne, tagliatelle, carbonara, bolognese, ragu',
  ),
  _a('lasagne', 'lasagne, lasagna, cannelloni, moussaka'),
  _a('pizza', 'pizza, calzone, focaccia'),
  _a('risotto', 'risotto, paella, pilaf, pilau, jambalaya'),
  _a('rice-bowl', 'rice, biryani, donburi, bibimbap, fried rice'),
  _a('grain-bowl', 'grain bowl, buddha bowl, quinoa, couscous, bulgur, farro'),
  _a(
    'soup-bowl',
    'soup, broth, bisque, chowder, consomme, minestrone, gazpacho',
  ),
  _a('salad-bowl', 'salad, slaw, coleslaw, tabbouleh, caesar'),
  _a('sandwich', 'sandwich, sarnie, panini, toastie, club, blt, reuben'),
  _a('burger', 'burger, cheeseburger, patty, sliders'),
  _a('hot-dog', 'hot dog, hotdog, bratwurst in a bun'),
  _a('wrap', 'wrap, burrito, shawarma, gyro, kebab wrap, quesadilla'),
  _a('taco', 'taco, tacos, tostada, enchilada, fajita, fajitas'),
  _a('sushi', 'sushi, maki, nigiri, sashimi, poke'),
  _a('dumplings', 'dumpling, dumplings, gyoza, pierogi, wonton, dim sum, bao'),
  _a('stir-fry', 'stir fry, stirfry, wok, teriyaki, szechuan'),
  _a('roast-dinner', 'roast dinner, sunday roast, carvery'),
  _a('bbq-grill', 'barbecue, bbq, grilled, griddled, char siu, brisket'),
  _a('pie-slice', 'apple pie, pecan pie, key lime, pumpkin pie, custard tart'),
  _a('tart', 'tart, galette, quiche, frangipane'),
  _a('cheesecake', 'cheesecake'),
  _a('cake-slice', 'cake, sponge, gateau, victoria, battenberg, tiramisu'),
  _a('cupcake', 'cupcake, fairy cake, muffin'),
  _a('cookie', 'cookie, cookies, biscuit, biscuits, shortbread, flapjack'),
  _a('brownie', 'brownie, blondie, fudge'),
  _a('pancakes', 'pancake, pancakes, crepe, crepes, blini'),
  _a('waffle', 'waffle, waffles'),
  _a('french-toast', 'french toast, eggy bread'),
  _a(
    'porridge-jar',
    'porridge, oats, oatmeal, overnight oats, granola, muesli, bircher',
  ),
  _a('yoghurt-pot', 'yoghurt, yogurt, parfait, fromage frais'),
  _a('smoothie', 'smoothie, shake, protein shake, juice, lassi'),
  _a('omelette', 'omelette, omelet, frittata, tortilla espanola, shakshuka'),
  _a(
    'fried-egg',
    'fried egg, poached egg, eggs benedict, scrambled eggs, boiled egg',
  ),
  _a('toast', 'toast, bruschetta, crostini, avocado toast'),
  _a('bagel', 'bagel, lox'),
  _a('croissant', 'croissant, pain au chocolat, danish, pastry'),
  _a(
    'bread-loaf',
    'bread, loaf, sourdough, focaccia loaf, brioche, challah, soda bread',
  ),
  _a('baguette', 'baguette, ciabatta, roll, rolls, bap'),
  _a('scone', 'scone, scones, cream tea'),
  _a('doughnut', 'doughnut, donut, churros, beignet'),
  _a('ice-cream', 'ice cream, gelato, sorbet, sundae'),
  _a('popsicle', 'popsicle, ice lolly, lolly'),
  _a(
    'pudding',
    'pudding, trifle, crumble, cobbler, eton mess, panna cotta, mousse',
  ),
  _a('custard', 'custard, creme brulee, flan, creme caramel'),
  _a('jelly', 'jelly, jello, gelatin'),
  _a('cheese-board', 'cheese board, charcuterie, antipasti, ploughmans'),
  _a('tapas-plate', 'tapas, mezze, meze, small plates'),
  _a(
    'dip-bowl',
    'dip, hummus, guacamole, salsa, tzatziki, baba ganoush, aioli',
  ),
  _a(
    'sauce-jug',
    'sauce, gravy, pesto, chimichurri, marinade, dressing, vinaigrette',
  ),
  _a('stock-pot', 'stock, bone broth, bouillon'),
  _a('pickle-jar', 'pickle, pickles, pickled, kimchi, sauerkraut, ferment'),
  _a('jam-jar', 'jam, preserve, marmalade, chutney, compote, curd'),

  // ---- Proteins ---------------------------------------------------------
  _a('roast-chicken', 'roast chicken, whole chicken, rotisserie'),
  _a('chicken-pieces', 'chicken, poussin, drumstick, thigh, wings'),
  _a('turkey', 'turkey'),
  _a('duck', 'duck, goose'),
  _a('steak', 'steak, sirloin, ribeye, fillet steak, rump'),
  _a('beef-joint', 'beef, brisket joint, silverside, topside'),
  _a('pork-chop', 'pork, chop, chops, gammon, ham, loin'),
  _a('ribs', 'ribs, rack of ribs, short rib'),
  _a('bacon', 'bacon, pancetta, lardons'),
  _a('sausages', 'sausage, sausages, chorizo, salami, banger, bangers'),
  _a('meatballs', 'meatball, meatballs, kofta, frikadeller'),
  _a('lamb', 'lamb, mutton, shank'),
  _a('fish-fillet', 'fish, cod, haddock, plaice, sea bass, hake, pollock'),
  _a('salmon', 'salmon, trout'),
  _a('tuna', 'tuna, mackerel, sardine, sardines, anchovy'),
  _a('prawns', 'prawn, prawns, shrimp, langoustine'),
  _a('mussels', 'mussels, clams, oysters, scallops'),
  _a('crab', 'crab, lobster, crayfish'),
  _a('squid', 'squid, calamari, octopus'),
  _a('tofu', 'tofu, tempeh, seitan'),
  _a(
    'beans',
    'beans, black beans, kidney beans, cannellini, butter beans, baked beans',
  ),
  _a('lentils', 'lentil, split peas'),
  _a('chickpeas', 'chickpea, chickpeas, falafel'),
  _a('eggs', 'egg, eggs'),

  // ---- Produce ----------------------------------------------------------
  _a('tomato', 'tomato, tomatoes, passata'),
  _a('onion', 'onion, onions, shallot, shallots'),
  _a('garlic', 'garlic'),
  _a('potato', 'potato, potatoes, mash, chips, fries, wedges, gratin, rosti'),
  _a('sweet-potato', 'sweet potato, yam'),
  _a('carrot', 'carrot, carrots, parsnip, parsnips, swede, turnip'),
  _a('broccoli', 'broccoli, tenderstem, purple sprouting'),
  _a('cauliflower', 'cauliflower, romanesco'),
  _a('cabbage', 'cabbage, sprouts, brussels, pak choi, bok choy'),
  _a('leafy-greens', 'spinach, kale, chard, rocket, lettuce, watercress'),
  _a('pepper', 'pepper, peppers, capsicum, bell pepper'),
  _a('chilli-pepper', 'chilli pepper, jalapeno, habanero, scotch bonnet'),
  _a('aubergine', 'aubergine, eggplant'),
  _a('courgette', 'courgette, zucchini, marrow'),
  _a(
    'mushroom',
    'mushroom, mushrooms, portobello, shiitake, chestnut mushrooms',
  ),
  _a('squash', 'squash, pumpkin, butternut'),
  _a('corn', 'corn, sweetcorn, cob, polenta'),
  _a('peas', 'pea, peas, mangetout, sugar snap'),
  _a('green-beans', 'green beans, runner beans, french beans'),
  _a('asparagus', 'asparagus, samphire'),
  _a('avocado', 'avocado'),
  _a('cucumber', 'cucumber, gherkin'),
  _a('beetroot', 'beetroot, beet, beets'),
  _a('leek', 'leek, leeks, spring onion, scallion'),
  _a('celery', 'celery, celeriac, fennel'),
  _a(
    'herbs',
    'herb, herbs, basil, coriander, cilantro, parsley, thyme, rosemary, sage, mint, dill',
  ),
  _a('lemon', 'lemon, lemons, lime, limes'),
  _a('orange', 'orange, oranges, clementine, satsuma, grapefruit'),
  _a('apple', 'apple, apples'),
  _a('pear', 'pear, pears, quince'),
  _a('banana', 'banana, bananas, plantain'),
  _a(
    'berries',
    'berry, berries, raspberry, raspberries, blackberry, blackberries, cranberry',
  ),
  _a('strawberries', 'strawberry, strawberries'),
  _a('blueberries', 'blueberry, blueberries'),
  _a('grapes', 'grape, grapes, raisin, raisins, sultanas'),
  _a(
    'stone-fruit',
    'peach, peaches, nectarine, plum, plums, apricot, cherry, cherries',
  ),
  _a('melon', 'melon, watermelon, cantaloupe'),
  _a('pineapple', 'pineapple'),
  _a('mango', 'mango, papaya, passion fruit, guava'),
  _a('fig', 'fig, figs, date, dates, pomegranate'),
  _a('coconut', 'coconut'),
  _a(
    'nuts',
    'nut, nuts, almond, almonds, walnut, walnuts, pecan, pistachio, hazelnut, cashew, peanut',
  ),
  _a(
    'seeds',
    'seed, seeds, sesame, sunflower seeds, pumpkin seeds, chia, flax',
  ),
  _a('olives', 'olive, olives, caper, capers'),

  // ---- Dairy and pantry -------------------------------------------------
  _a(
    'cheese-wedge',
    'cheese, cheddar, parmesan, mozzarella, feta, halloumi, brie, blue cheese',
  ),
  _a('butter', 'butter, ghee'),
  _a('milk-bottle', 'milk, buttermilk, oat milk, almond milk'),
  _a('cream', 'cream, creme fraiche, mascarpone, ricotta'),
  _a('flour-sack', 'flour, dough, pastry dough, batter, semolina'),
  _a('sugar', 'sugar, caster, icing sugar, syrup, treacle, molasses'),
  _a('honey-jar', 'honey, maple syrup, agave'),
  _a('oil-bottle', 'oil, olive oil, vinegar, balsamic'),
  _a(
    'spice-jars',
    'spice, spices, cumin, paprika, turmeric, cinnamon, saffron, masala, curry powder',
  ),
  _a('salt-pepper', 'salt, peppercorn, seasoning'),
  _a('chocolate', 'chocolate, cocoa, cacao, ganache, praline'),
  _a('coffee', 'coffee, espresso, latte, cappuccino, mocha'),
  _a('tea', 'tea, chai, matcha, infusion'),
  _a('wine-glass', 'wine, mulled wine, sangria, prosecco'),
  _a('beer', 'beer, ale, stout, cider'),
  _a('cocktail', 'cocktail, margarita, mojito, negroni, spritz, punch'),

  // ---- Where the food came from, when nothing else fits -----------------
  _a('takeaway-box', 'takeaway, takeout, delivery, drive thru'),
  _a('lunchbox', 'lunchbox, bento, packed lunch, meal prep'),
  _a('picnic', 'picnic, hamper'),
  _a('breakfast-tray', 'breakfast, brunch, fry up, full english'),
  _a('celebration-cake', 'birthday, celebration, wedding cake, christmas cake'),
  _a('festive-table', 'christmas, thanksgiving, easter, feast'),
];
