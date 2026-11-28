# Hearth recipe artwork — brief

A brief for whoever or whatever draws the set: an illustrator, a commission,
or an image model driven by the prompt in §2. Everything below §3 is
generated from `lib/domain/recipes/recipe_artwork.dart` by
`dart run tool/write_artwork_brief.dart`, and a test fails if the two drift —
the registry is the source of truth, not this file.

---

## 1. What this is for

Hearth draws a small picture beside each recipe in its library. A recipe with
a photograph shows the photograph; a recipe with its own generated sketch
shows the sketch; everything else — which is most of a real household's
library — shows one of these.

They are **archetypes, not portraits**. There is no drawing of "Granny's
Tuesday chilli"; there is a drawing of a bowl of chilli, and every chilli in
the house wears it. At the 36 to 48 points a library row gives a thumbnail,
nothing more specific would be legible anyway.

They are drawn once, reviewed once, licensed once, and shipped with the app,
so they cost nothing at runtime and work with the aeroplane mode on.

## 2. The prompt

> You are drawing a set of food illustrations for Hearth, a warm, rustic
> household recipe app. The set must look like one hand drew all of it in one
> sitting.
>
> **Style.** Nineteenth-century engraving, as in an old cookery book or a
> seed catalogue: fine ink line work, cross-hatching for shadow, a heavier
> outline against finer interior lines, and a light drawn shadow on the
> ground beneath the subject. Warm and hand-made, never clinical. No
> perspective tricks, no dramatic lighting, no styling — the object, drawn
> plainly, slightly from above at about a 20-degree angle, as if it were on
> the table in front of you.
>
> **One ink.** The whole drawing is a single dark ink on nothing. No colour,
> no second tone, no grey fills that are not made of hatching. Shading is
> line density: more lines close together where it is darker. The app tints
> the finished drawing to its own palette and runs in both a light and a dark
> theme, so any colour you add will be thrown away and any opaque background
> will ruin it.
>
> **Transparent background, always.** Deliver PNG with a real alpha channel.
> The paper is not in the picture; the app's own page is the paper. Do not
> draw a frame, a border, a circle behind the subject, a label, a caption, a
> signature or a watermark.
>
> **Grain belongs in the ink.** If you give the line a slightly broken,
> printed quality — the ink catching and missing as it would on rough paper —
> put it in the alpha of the strokes themselves, not as a layer of noise over
> the whole square. Noise over the square becomes a grey box the moment the
> app tints it.
>
> **Consistent across the set.** Same ink weight, same hatching angle and
> density, same eye level, same amount of the frame filled. Draw them in
> batches and compare each new one against the ones already done. A set where
> the bowl is delicate and the cabbage is bold is worse than a set that is
> uniformly plain.
>
> **Composition.** One subject, centred, occupying about 85 per cent of the
> square with even margins. Square canvas, 1024 by 1024. Where a dish is
> normally served in something, draw the vessel — a stew is a pot, a soup is
> a bowl, oats are a jar. Where the subject is an ingredient, draw the
> ingredient plainly, two or three of them if one looks lonely. No cutlery,
> no napkins, no table settings, no hands, no people, unless the name below
> asks for them.
>
> **Legibility is the test.** Each drawing is shown at 40 points on a phone.
> Squint at it at that size: if the subject is not instantly recognisable,
> simplify it until it is. Detail that disappears at 40 points is fine —
> detail that turns into a grey smudge is not, so keep hatching open rather
> than dense.
>
> **File names.** Exactly the id given in the list, lower case, hyphens, with
> a `.png` extension: `pot-pie.png`, `stew-pot.png`. Nothing else in the file
> name.
>
> **Size.** 512 by 512 is what the app wants. Batch one came at 1024 and was
> halved on the way in, which is fine but is work; 512 is the delivery size.
> If you can also give WebP, do — a hundred and fifty drawings at batch
> one's PNG weight is twenty megabytes of app, and WebP is a quarter of
> that.
>
> Draw the following subjects. The words after each id are what a recipe
> might be called to deserve that drawing — they are there to tell you what
> the picture has to evoke, not to be written on it.

## 3. Checking a batch

Before anything is accepted into the app:

1. Open one on a white page and one on a near-black page. If the drawing is
   invisible on either, its background is not transparent.
2. Tint one to a mid-brown. Shading made of hatching survives; shading made
   of grey fill turns into a flat shape.
3. Shrink one to 40 points. If it is a smudge, the hatching is too dense.
4. Put six of them side by side. If one looks like a different artist, it is.

Added under `assets/art/`, with the id added to `kArtworkShipped` in
`lib/app/widgets/recipe_art.dart` in the same change — the app only draws
what that set names, so a file alone does nothing.

Those four checks are also a test. `artwork_is_line_art_test.dart` opens
every drawing that ships and measures it: square and at least 450 pixels,
nothing in the corners, mostly transparent, one ink with no colour in it,
and partial alpha somewhere so the grain has somewhere to live. None of
those failures is visible in a folder of PNGs on a white page, which is
where a batch gets looked at.

## 3a. Batch log

**Batch one, November 2026** — six drawings: `chilli-bowl`, `porridge-jar`,
`pot-pie`, `ramen-bowl`, `soup-bowl`, `stew-pot`. All six passed on the
first pass: corners fully transparent, 70 to 87 per cent of each image
empty, no colour anywhere, and 13 to 30 per cent partial alpha — the ink
catching on the paper, exactly as asked. Delivered at 1024 and halved to
512 on the way in. Shipped as PNG; see the WebP note above.

## 4. The subjects

<!-- BEGIN GENERATED SUBJECTS -->

150 drawings.

- `pot-pie` — pot pie, chicken pie, steak pie, shepherds pie, cottage pie
- `stew-pot` — stew, casserole, braise, braised, pot roast, hotpot, ragout
- `chilli-bowl` — chilli, chili, con carne
- `curry-bowl` — curry, korma, tikka masala, vindaloo, rogan josh, dhansak, dal, dahl
- `tagine` — tagine, tajine
- `ramen-bowl` — ramen, tonkotsu
- `pho-bowl` — pho
- `noodle-bowl` — noodles, noodle, lo mein, chow mein, pad thai, udon, soba
- `pasta-plate` — pasta, spaghetti, linguine, penne, tagliatelle, carbonara, bolognese, ragu
- `lasagne` — lasagne, lasagna, cannelloni, moussaka
- `pizza` — pizza, calzone, focaccia
- `risotto` — risotto, paella, pilaf, pilau, jambalaya
- `rice-bowl` — rice, biryani, donburi, bibimbap, fried rice
- `grain-bowl` — grain bowl, buddha bowl, quinoa, couscous, bulgur, farro
- `soup-bowl` — soup, broth, bisque, chowder, consomme, minestrone, gazpacho
- `salad-bowl` — salad, slaw, coleslaw, tabbouleh, caesar
- `sandwich` — sandwich, sarnie, panini, toastie, club, blt, reuben
- `burger` — burger, cheeseburger, patty, sliders
- `hot-dog` — hot dog, hotdog, bratwurst in a bun
- `wrap` — wrap, burrito, shawarma, gyro, kebab wrap, quesadilla
- `taco` — taco, tacos, tostada, enchilada, fajita, fajitas
- `sushi` — sushi, maki, nigiri, sashimi, poke
- `dumplings` — dumpling, dumplings, gyoza, pierogi, wonton, dim sum, bao
- `stir-fry` — stir fry, stirfry, wok, teriyaki, szechuan
- `roast-dinner` — roast dinner, sunday roast, carvery
- `bbq-grill` — barbecue, bbq, grilled, griddled, char siu, brisket
- `pie-slice` — apple pie, pecan pie, key lime, pumpkin pie, custard tart
- `tart` — tart, galette, quiche, frangipane
- `cheesecake` — cheesecake
- `cake-slice` — cake, sponge, gateau, victoria, battenberg, tiramisu
- `cupcake` — cupcake, fairy cake, muffin
- `cookie` — cookie, cookies, biscuit, biscuits, shortbread, flapjack
- `brownie` — brownie, blondie, fudge
- `pancakes` — pancake, pancakes, crepe, crepes, blini
- `waffle` — waffle, waffles
- `french-toast` — french toast, eggy bread
- `porridge-jar` — porridge, oats, oatmeal, overnight oats, granola, muesli, bircher
- `yoghurt-pot` — yoghurt, yogurt, parfait, fromage frais
- `smoothie` — smoothie, shake, protein shake, juice, lassi
- `omelette` — omelette, omelet, frittata, tortilla espanola, shakshuka
- `fried-egg` — fried egg, poached egg, eggs benedict, scrambled eggs, boiled egg
- `toast` — toast, bruschetta, crostini, avocado toast
- `bagel` — bagel, lox
- `croissant` — croissant, pain au chocolat, danish, pastry
- `bread-loaf` — bread, loaf, sourdough, focaccia loaf, brioche, challah, soda bread
- `baguette` — baguette, ciabatta, roll, rolls, bap
- `scone` — scone, scones, cream tea
- `doughnut` — doughnut, donut, churros, beignet
- `ice-cream` — ice cream, gelato, sorbet, sundae
- `popsicle` — popsicle, ice lolly, lolly
- `pudding` — pudding, trifle, crumble, cobbler, eton mess, panna cotta, mousse
- `custard` — custard, creme brulee, flan, creme caramel
- `jelly` — jelly, jello, gelatin
- `cheese-board` — cheese board, charcuterie, antipasti, ploughmans
- `tapas-plate` — tapas, mezze, meze, small plates
- `dip-bowl` — dip, hummus, guacamole, salsa, tzatziki, baba ganoush, aioli
- `sauce-jug` — sauce, gravy, pesto, chimichurri, marinade, dressing, vinaigrette
- `stock-pot` — stock, bone broth, bouillon
- `pickle-jar` — pickle, pickles, pickled, kimchi, sauerkraut, ferment
- `jam-jar` — jam, preserve, marmalade, chutney, compote, curd
- `roast-chicken` — roast chicken, whole chicken, rotisserie
- `chicken-pieces` — chicken, poussin, drumstick, thigh, wings
- `turkey` — turkey
- `duck` — duck, goose
- `steak` — steak, sirloin, ribeye, fillet steak, rump
- `beef-joint` — beef, brisket joint, silverside, topside
- `pork-chop` — pork, chop, chops, gammon, ham, loin
- `ribs` — ribs, rack of ribs, short rib
- `bacon` — bacon, pancetta, lardons
- `sausages` — sausage, sausages, chorizo, salami, banger, bangers
- `meatballs` — meatball, meatballs, kofta, frikadeller
- `lamb` — lamb, mutton, shank
- `fish-fillet` — fish, cod, haddock, plaice, sea bass, hake, pollock
- `salmon` — salmon, trout
- `tuna` — tuna, mackerel, sardine, sardines, anchovy
- `prawns` — prawn, prawns, shrimp, langoustine
- `mussels` — mussels, clams, oysters, scallops
- `crab` — crab, lobster, crayfish
- `squid` — squid, calamari, octopus
- `tofu` — tofu, tempeh, seitan
- `beans` — beans, black beans, kidney beans, cannellini, butter beans, baked beans
- `lentils` — lentil, split peas
- `chickpeas` — chickpea, chickpeas, falafel
- `eggs` — egg, eggs
- `tomato` — tomato, tomatoes, passata
- `onion` — onion, onions, shallot, shallots
- `garlic` — garlic
- `potato` — potato, potatoes, mash, chips, fries, wedges, gratin, rosti
- `sweet-potato` — sweet potato, yam
- `carrot` — carrot, carrots, parsnip, parsnips, swede, turnip
- `broccoli` — broccoli, tenderstem, purple sprouting
- `cauliflower` — cauliflower, romanesco
- `cabbage` — cabbage, sprouts, brussels, pak choi, bok choy
- `leafy-greens` — spinach, kale, chard, rocket, lettuce, watercress
- `pepper` — pepper, peppers, capsicum, bell pepper
- `chilli-pepper` — chilli pepper, jalapeno, habanero, scotch bonnet
- `aubergine` — aubergine, eggplant
- `courgette` — courgette, zucchini, marrow
- `mushroom` — mushroom, mushrooms, portobello, shiitake, chestnut mushrooms
- `squash` — squash, pumpkin, butternut
- `corn` — corn, sweetcorn, cob, polenta
- `peas` — pea, peas, mangetout, sugar snap
- `green-beans` — green beans, runner beans, french beans
- `asparagus` — asparagus, samphire
- `avocado` — avocado
- `cucumber` — cucumber, gherkin
- `beetroot` — beetroot, beet, beets
- `leek` — leek, leeks, spring onion, scallion
- `celery` — celery, celeriac, fennel
- `herbs` — herb, herbs, basil, coriander, cilantro, parsley, thyme, rosemary, sage, mint, dill
- `lemon` — lemon, lemons, lime, limes
- `orange` — orange, oranges, clementine, satsuma, grapefruit
- `apple` — apple, apples
- `pear` — pear, pears, quince
- `banana` — banana, bananas, plantain
- `berries` — berry, berries, raspberry, raspberries, blackberry, blackberries, cranberry
- `strawberries` — strawberry, strawberries
- `blueberries` — blueberry, blueberries
- `grapes` — grape, grapes, raisin, raisins, sultanas
- `stone-fruit` — peach, peaches, nectarine, plum, plums, apricot, cherry, cherries
- `melon` — melon, watermelon, cantaloupe
- `pineapple` — pineapple
- `mango` — mango, papaya, passion fruit, guava
- `fig` — fig, figs, date, dates, pomegranate
- `coconut` — coconut
- `nuts` — nut, nuts, almond, almonds, walnut, walnuts, pecan, pistachio, hazelnut, cashew, peanut
- `seeds` — seed, seeds, sesame, sunflower seeds, pumpkin seeds, chia, flax
- `olives` — olive, olives, caper, capers
- `cheese-wedge` — cheese, cheddar, parmesan, mozzarella, feta, halloumi, brie, blue cheese
- `butter` — butter, ghee
- `milk-bottle` — milk, buttermilk, oat milk, almond milk
- `cream` — cream, creme fraiche, mascarpone, ricotta
- `flour-sack` — flour, dough, pastry dough, batter, semolina
- `sugar` — sugar, caster, icing sugar, syrup, treacle, molasses
- `honey-jar` — honey, maple syrup, agave
- `oil-bottle` — oil, olive oil, vinegar, balsamic
- `spice-jars` — spice, spices, cumin, paprika, turmeric, cinnamon, saffron, masala, curry powder
- `salt-pepper` — salt, peppercorn, seasoning
- `chocolate` — chocolate, cocoa, cacao, ganache, praline
- `coffee` — coffee, espresso, latte, cappuccino, mocha
- `tea` — tea, chai, matcha, infusion
- `wine-glass` — wine, mulled wine, sangria, prosecco
- `beer` — beer, ale, stout, cider
- `cocktail` — cocktail, margarita, mojito, negroni, spritz, punch
- `takeaway-box` — takeaway, takeout, delivery, drive thru
- `lunchbox` — lunchbox, bento, packed lunch, meal prep
- `picnic` — picnic, hamper
- `breakfast-tray` — breakfast, brunch, fry up, full english
- `celebration-cake` — birthday, celebration, wedding cake, christmas cake
- `festive-table` — christmas, thanksgiving, easter, feast
<!-- END GENERATED SUBJECTS -->
