import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/adapters/barcode_scanner.dart';
import '../../data/adapters/label_reader.dart';
import '../../data/adapters/nutrition_lookup.dart';
import '../../data/adapters/nutrition_source.dart';
import '../../data/adapters/photo_picker.dart';
import '../../data/adapters/recipe_ai.dart';
import '../../data/local/shopping_store.dart';
import '../../data/repositories/food_repository.dart';
import '../../domain/foods/pack_size_queue.dart';
import '../../domain/models/food.dart';
import '../../domain/models/recipe.dart';
import '../../domain/shopping/shopping_line.dart';
import '../../domain/units/quantity.dart';

/// Every food with no pack size, worst first (spec §5.7).
///
/// Three sources, and all three have to have answered. A queue built while
/// the shopping list is still loading would file every food under "everything
/// else" and then reorder itself under somebody's finger — which on a list of
/// several hundred is worse than a moment's spinner.
final Provider<AsyncValue<PackSizeQueue>> packSizeQueueProvider =
    Provider<AsyncValue<PackSizeQueue>>((Ref ref) {
      final AsyncValue<List<Food>> foods = ref.watch(foodLibraryProvider);
      final AsyncValue<List<Recipe>> recipes = ref.watch(recipeLibraryProvider);
      final AsyncValue<ShoppingListSnapshot?> list = ref.watch(
        shoppingListProvider,
      );

      // An error travels rather than being drawn as a spinner that never
      // stops. The screen says the library could not be read, which is a
      // thing somebody can act on.
      for (final AsyncValue<Object?> source in <AsyncValue<Object?>>[
        foods,
        recipes,
        list,
      ]) {
        if (source case AsyncError<Object?>(
          :final Object error,
          :final StackTrace stackTrace,
        )) {
          return AsyncValue<PackSizeQueue>.error(error, stackTrace);
        }
      }

      if (!foods.hasValue || !recipes.hasValue || !list.hasValue) {
        return const AsyncValue<PackSizeQueue>.loading();
      }

      final Map<String, int> uses = <String, int>{};
      for (final Recipe recipe in recipes.value!) {
        // Per recipe, not per line: a recipe that names chopped tomatoes
        // twice wants them once.
        final Set<String> named = <String>{
          for (final RecipeIngredient line in recipe.allIngredients)
            if (line.foodId case final String id) id,
        };
        for (final String id in named) {
          uses[id] = (uses[id] ?? 0) + 1;
        }
      }

      return AsyncValue<PackSizeQueue>.data(
        PackSizeQueue.build(
          foods: foods.value!,
          onShoppingList: <String>{
            for (final ShoppingLine line in list.value?.lines ?? const [])
              if (line.foodId case final String id) id,
          },
          recipeUses: uses,
        ),
      );
    });

/// A pack size somebody has been *offered*, and has not accepted.
///
/// Nothing here is on a food until the save button is pressed (CLAUDE.md
/// rule 4). The distinction is load-bearing rather than ceremonial: a wrong
/// pack size does not fail, it silently buys the wrong amount, and the review
/// screen is the only thing between a misread box and a shopping list that
/// says four jars.
@immutable
class PackProposal {
  const PackProposal({
    required this.food,
    required this.size,
    required this.from,
    required this.selected,
    this.uncertain = const <AiUncertainty>[],
  });

  /// The food as it stands. Carried rather than looked up again at save time,
  /// so what is written is the row that was shown.
  final Food food;

  final Quantity size;

  /// Where it came from, in the words the row shows — "Open Food Facts",
  /// "the photo". Provenance is half of what makes this reviewable.
  final String from;

  /// Whether the save will include it.
  final bool selected;

  /// What the reader could not be sure of. A flagged reading starts
  /// unselected: the model has said in as many words that this is the one to
  /// look at, and pre-ticking it would be Hearth ignoring its own warning.
  final List<AiUncertainty> uncertain;

  bool get isFlagged => uncertain.isNotEmpty;

  PackProposal toggled(bool value) => PackProposal(
    food: food,
    size: size,
    from: from,
    selected: value,
    uncertain: uncertain,
  );
}

/// How far a run over the barcoded foods has got.
@immutable
class PackSweep {
  const PackSweep({required this.done, required this.total});

  final int done;
  final int total;

  bool get isRunning => done < total;
}

@immutable
class PackFillState {
  const PackFillState({
    this.proposals = const <String, PackProposal>{},
    this.misses = const <String, String>{},
    this.busy = const <String>{},
    this.sweep,
  });

  /// By food id, in no order: the screen draws them against the queue.
  final Map<String, PackProposal> proposals;

  /// Foods that were asked and had nothing to say, with the sentence to show.
  ///
  /// Kept rather than left blank, because "nobody knows" and "not asked yet"
  /// look identical on a row and only one of them is worth asking again.
  final Map<String, String> misses;

  /// Foods with a question in flight.
  final Set<String> busy;

  /// The barcode run, while there is one.
  final PackSweep? sweep;

  int get selectedCount =>
      proposals.values.where((PackProposal p) => p.selected).length;

  PackFillState copyWith({
    Map<String, PackProposal>? proposals,
    Map<String, String>? misses,
    Set<String>? busy,
    PackSweep? sweep,
  }) => PackFillState(
    proposals: proposals ?? this.proposals,
    misses: misses ?? this.misses,
    busy: busy ?? this.busy,
    sweep: sweep ?? this.sweep,
  );
}

/// Finding pack sizes for foods that already have none (spec §5.7).
///
/// Three ways in, and every one of them stops short of writing. The barcode
/// run and the photograph both land here as proposals; the third way — typing
/// it — goes to the food editor, which is a review screen in its own right.
class PackFillController extends Notifier<PackFillState> {
  @override
  PackFillState build() {
    // Reset rather than assumed false: a Notifier is rebuilt after a dispose,
    // and a flag left true would silently swallow the next screen's state.
    _gone = false;
    ref.onDispose(() => _gone = true);
    return const PackFillState();
  }

  /// True once the screen has gone.
  ///
  /// This provider is auto-disposed and its work is a chain of awaited network
  /// calls, so a run started on a screen somebody then leaves is still in
  /// flight when the notifier is thrown away — and writing `state` on a
  /// disposed notifier throws, out of a future nobody is awaiting.
  bool _gone = false;

  /// Beyond this the function refuses the photo anyway. Caught here so the
  /// answer arrives before the upload rather than after it. Mirrors
  /// [LabelScanController.maxImageBytes].
  static const int maxImageBytes = 5 * 1024 * 1024;

  /// Cancels an in-flight run when the screen goes away or a new one starts.
  int _run = 0;

  /// Asks the nutrition chain about every barcode in [gaps].
  ///
  /// One at a time rather than all at once. These are somebody else's servers
  /// and this is hundreds of requests; a burst is how a household gets rate
  /// limited, and the progress line means the wait is legible anyway.
  Future<void> lookUpAll(List<PackSizeGap> gaps) async {
    final List<PackSizeGap> asking = <PackSizeGap>[
      for (final PackSizeGap gap in gaps)
        if (gap.canBeLookedUp && !state.proposals.containsKey(gap.food.id)) gap,
    ];
    if (asking.isEmpty) return;

    final int run = ++_run;
    _set(state.copyWith(sweep: PackSweep(done: 0, total: asking.length)));

    for (int i = 0; i < asking.length; i++) {
      // A newer run, or a screen that has gone: either way this one stops
      // rather than spending several hundred requests nobody will read.
      if (_run != run || _gone) return;
      await _ask(asking[i]);
      if (_run != run || _gone) return;
      _set(
        state.copyWith(
          sweep: PackSweep(done: i + 1, total: asking.length),
        ),
      );
    }
  }

  /// Asks about one food's barcode.
  Future<void> lookUpOne(PackSizeGap gap) async {
    if (!gap.canBeLookedUp) return;
    await _ask(gap);
  }

  Future<void> _ask(PackSizeGap gap) async {
    final String id = gap.food.id;
    _markBusy(id, true);
    try {
      final ({Quantity size, String from})? found = await _packFor(
        gap.barcode!,
      );
      if (found == null) {
        _miss(id, 'No pack size on record for that barcode.');
        return;
      }
      _propose(
        PackProposal(
          food: gap.food,
          size: found.size,
          from: found.from,
          // A database answering the exact barcode printed on the packet is
          // the strongest evidence there is short of the box itself, and it
          // is the same answer Hearth already accepts without any review at
          // all when a new food is scanned in. Ticked, therefore — the review
          // this screen owes is the chance to *untick*, across a run of
          // hundreds, not a tap per row that nobody would finish.
          selected: true,
        ),
      );
    } on Object {
      _miss(id, 'That lookup did not go through. Try it again.');
    } finally {
      _markBusy(id, false);
    }
  }

  /// The first pack size the outside world has for this barcode.
  ///
  /// The chain is walked source by source rather than through
  /// [NutritionLookup.byBarcode], for the one reason that would otherwise make
  /// this feature do nothing at all. That method stops at the first source
  /// with *a match*, and the first source is the household's own library —
  /// which has this food, by definition, and has it without a pack size. Every
  /// lookup would end there, holding the blank it started from. Here a match
  /// with no pack size is not an answer, so the chain keeps going.
  ///
  /// A library match is stepped over even when it does carry a pack size. Such
  /// a row is a duplicate of the food being filled in, and offering its pack
  /// size back under a database's name would dress the household's own guess
  /// up as evidence.
  Future<({Quantity size, String from})?> _packFor(String barcode) async {
    final NutritionLookup lookup = ref.read(nutritionLookupProvider);
    for (final NutritionSource source in lookup.sources) {
      for (final String variant in BarcodeVariants.of(barcode)) {
        final NutritionMatch? match = await source.byBarcode(variant);
        if (match == null || match.fromLibrary) continue;
        final Quantity? pack = match.food.packSize;
        if (pack != null && !pack.isZero) {
          return (size: pack, from: source.displayName);
        }
      }
    }
    return null;
  }

  /// Photographs one packet and reads its net contents.
  ///
  /// Picking and reading in one go, the same as the label sheet: there is
  /// nothing to arrange between the two, and a second tap for no decision is
  /// a second tap.
  Future<void> photograph(Food food, PhotoOrigin origin) async {
    final LabelReader? reader = ref.read(labelReaderProvider);
    if (reader == null) return;

    final PickedPhoto? picked = await ref
        .read(photoPickerProvider)
        .pick(origin);
    if (picked == null) return;

    if (picked.bytes.lengthInBytes > maxImageBytes) {
      // Desktop pickers ignore the downscaling the mobile ones apply, so a
      // full-resolution photo can arrive intact.
      _miss(
        food.id,
        'That photo is too big to send. One from your phone will be fine.',
      );
      return;
    }

    _markBusy(food.id, true);
    try {
      final PackReading reading = await reader.readPack(<AiImage>[
        AiImage.ofPhoto(picked),
      ]);
      final Quantity? size = reading.size;
      if (size == null) {
        _miss(
          food.id,
          reading.uncertain.isEmpty
              ? 'No net contents could be read off that photo.'
              : reading.uncertain.first.note,
        );
        return;
      }
      _propose(
        PackProposal(
          food: food,
          size: size,
          from: 'the photo',
          uncertain: reading.uncertain,
          // A flagged reading arrives unticked. The model has said which one
          // to look at; pre-ticking it would be Hearth overruling its own
          // warning on a value that fails silently.
          selected: reading.uncertain.isEmpty,
        ),
      );
    } on RecipeAiException catch (error) {
      _miss(food.id, error.message);
    } on Object {
      _miss(food.id, 'That did not go through. Try it again.');
    } finally {
      _markBusy(food.id, false);
    }
  }

  void toggle(String foodId) {
    final PackProposal? proposal = state.proposals[foodId];
    if (proposal == null) return;
    _set(
      state.copyWith(
        proposals: <String, PackProposal>{
          ...state.proposals,
          foodId: proposal.toggled(!proposal.selected),
        },
      ),
    );
  }

  /// Throws a proposal away without saving it.
  void discard(String foodId) {
    if (!state.proposals.containsKey(foodId)) return;
    _set(
      state.copyWith(
        proposals: <String, PackProposal>{...state.proposals}..remove(foodId),
      ),
    );
  }

  /// Writes every ticked proposal, and returns how many landed.
  ///
  /// The only write in this file, and the only one reachable from this
  /// screen. A proposal that fails to save stays on screen, ticked: a row
  /// that vanished would claim a pack size the food does not have.
  Future<int> saveSelected() async {
    final List<PackProposal> chosen = <PackProposal>[
      for (final PackProposal p in state.proposals.values)
        if (p.selected) p,
    ];
    if (chosen.isEmpty) return 0;

    // Read once, before the first await. This provider is auto-disposed, and
    // reading a ref after the screen has gone throws — mid-save is the worst
    // moment for that, because the writes before it have already landed.
    final FoodRepository foods = ref.read(foodRepositoryProvider);

    final Set<String> saved = <String>{};
    final Map<String, String> failed = <String, String>{};
    for (final PackProposal proposal in chosen) {
      try {
        await foods.save(proposal.food.withPackSize(proposal.size));
        saved.add(proposal.food.id);
      } on Object {
        failed[proposal.food.id] = 'That one could not be saved.';
      }
    }

    _set(
      state.copyWith(
        proposals: <String, PackProposal>{
          for (final MapEntry<String, PackProposal> e
              in state.proposals.entries)
            if (!saved.contains(e.key)) e.key: e.value,
        },
        misses: <String, String>{...state.misses, ...failed},
      ),
    );
    return saved.length;
  }

  void _propose(PackProposal proposal) {
    _set(
      state.copyWith(
        proposals: <String, PackProposal>{
          ...state.proposals,
          proposal.food.id: proposal,
        },
        misses: <String, String>{...state.misses}..remove(proposal.food.id),
      ),
    );
  }

  void _miss(String foodId, String why) {
    _set(
      state.copyWith(misses: <String, String>{...state.misses, foodId: why}),
    );
  }

  /// The one place `state` is written, so the disposed check cannot be
  /// forgotten at one of the eight call sites.
  void _set(PackFillState next) {
    if (_gone) return;
    state = next;
  }

  void _markBusy(String foodId, bool busy) {
    final Set<String> next = <String>{...state.busy};
    if (busy) {
      next.add(foodId);
    } else {
      next.remove(foodId);
    }
    _set(state.copyWith(busy: next));
  }
}

/// Auto-disposed: leaving the screen throws the unsaved proposals away.
///
/// That is the honest behaviour rather than a limitation. Nothing here has
/// been agreed to, and a proposal that survived a trip to the food editor and
/// back would be a pack size somebody had already decided against, waiting to
/// be saved by a button press meant for something else.
final NotifierProvider<PackFillController, PackFillState> packFillProvider =
    NotifierProvider<PackFillController, PackFillState>(
      PackFillController.new,
      isAutoDispose: true,
    );
