import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/app/theme/hearth_theme.dart';
import 'package:hearth/data/adapters/label_reader.dart';
import 'package:hearth/data/adapters/nutrition_lookup.dart';
import 'package:hearth/data/adapters/nutrition_source.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/data/local/editor_draft_store.dart';
import 'package:hearth/data/repositories/food_repository.dart';
import 'package:hearth/domain/models/food.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/features/foods/barcode_scan_screen.dart';
import 'package:hearth/features/foods/food_editor_screen.dart';
import 'package:hearth/features/foods/ingredient_food_capture.dart';
import 'package:hearth/features/foods/walmart_link_controller.dart';
import 'package:hearth/features/recipes/match_review_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../support/app_harness.dart' show pumpFrames;
import '../foods/label_scan_test.dart' show FakeCamera;

class ResolutionFoods extends Fake implements FoodRepository {
  final Map<String, Food> saved = {};
  final List<Food> attempts = [];
  int failuresLeft = 0;
  int? failAttempt;
  Future<void> Function(Food)? onSave;
  Future<List<Food>> Function(Food)? onDuplicates;

  @override
  Future<Food?> byId(String id) async => saved[id];
  @override
  Future<List<Food>> likelyDuplicatesOf(Food food) async =>
      onDuplicates == null ? [] : onDuplicates!(food);
  @override
  Future<void> save(Food food) async {
    attempts.add(food);
    if (failuresLeft > 0 || attempts.length == failAttempt) {
      if (failuresLeft > 0) failuresLeft--;
      throw StateError('Synthetic save failure');
    }
    await onSave?.call(food);
    saved[food.id] = food;
  }
}

class ResolutionDrafts extends Fake implements EditorDraftStore {
  final List<EditorDraft> saved = [];
  int clears = 0;
  int clearFailuresLeft = 0;
  EditorDraft? found;
  Future<EditorDraft?> Function()? onFind;
  @override
  Future<EditorDraft?> find({required String kind, String? targetId}) async =>
      onFind == null ? found : onFind!();
  @override
  Future<void> save(EditorDraft draft, {required DateTime at}) async =>
      saved.add(draft);
  @override
  Future<void> clear({required String kind, String? targetId}) async {
    clears++;
    if (clearFailuresLeft > 0) {
      clearFailuresLeft--;
      throw StateError('Synthetic draft cleanup failure');
    }
    found = null;
  }
}

class ResolutionSource implements NutritionSource {
  ResolutionSource({this.answers = const {}, this.barcodes = const {}});
  Map<String, List<NutritionMatch>> answers;
  final Map<String, NutritionMatch> barcodes;
  final List<String> queries = [];
  @override
  String get displayName => 'Synthetic resolution fixture';
  @override
  Future<NutritionMatch?> byBarcode(String barcode) async => barcodes[barcode];
  @override
  Future<List<NutritionMatch>> search(String query, {int limit = 20}) async {
    queries.add(query);
    return answers[query] ?? [];
  }
}

class ResolutionIdentity extends Notifier<String> {
  @override
  String build() => 'first';
  void change() => state = 'second';
}

final resolutionIdentity = NotifierProvider<ResolutionIdentity, String>(
  ResolutionIdentity.new,
);

class ResolutionHarness {
  ResolutionHarness(this.foods, this.source);
  final ResolutionFoods foods;
  final ResolutionSource source;
  final ResolutionDrafts drafts = ResolutionDrafts();
  final ResolutionDrafts secondDrafts = ResolutionDrafts();
  late ProviderContainer container;
  late GoRouter router;
  ReviewedIngredientMatches? result;
  bool returned = false;
}

/// Real screen widgets and real push/pop routes with the coordinator's typed
/// extra contract. The shared app router is coordinator-owned; its integration
/// is separately exercised by the existing full-app ingredient tests.
Future<ResolutionHarness> pumpResolution(
  WidgetTester tester, {
  String lines = '100 g olive oil\n200 g cottage cheese\n1 pinch asafoetida',
  ResolutionFoods? foods,
  ResolutionSource? source,
  LabelReader? reader,
  bool cameraAvailable = false,
  List<AiEstimate> estimates = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final harness = ResolutionHarness(
    foods ?? ResolutionFoods(),
    source ?? ResolutionSource(),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  harness.container = ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWith(
        (ref) => ref.watch(resolutionIdentity),
      ),
      currentHouseholdIdProvider.overrideWith(
        (ref) => 'household-${ref.watch(resolutionIdentity)}',
      ),
      foodRepositoryProvider.overrideWithValue(harness.foods),
      editorDraftStoreProvider.overrideWith(
        (ref) => ref.watch(resolutionIdentity) == 'first'
            ? harness.drafts
            : harness.secondDrafts,
      ),
      foodLibraryProvider.overrideWith(
        (ref) => Stream.value(harness.foods.saved.values.toList()),
      ),
      nutritionLookupProvider.overrideWithValue(
        NutritionLookup([harness.source]),
      ),
      cameraScanningAvailableProvider.overrideWithValue(cameraAvailable),
      labelReaderProvider.overrideWithValue(reader),
      photoPickerProvider.overrideWithValue(FakeCamera()),
      walmartLinkReaderProvider.overrideWithValue(null),
    ],
  );
  harness.router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: FilledButton(
              child: const Text('Review ingredients'),
              onPressed: () async {
                harness.result = await showMatchReview(
                  context,
                  ingredients: lines
                      .split('\n')
                      .map(IngredientParser.parse)
                      .toList(),
                  estimates: estimates,
                );
                harness.returned = true;
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/elsewhere',
        builder: (context, state) => const Scaffold(body: Text('Another task')),
      ),
      GoRoute(
        path: '/food/scan',
        builder: (context, state) => IngredientFoodRouteExtra.wrapRoute(
          state.extra,
          BarcodeScanScreen(pickFood: state.uri.queryParameters['pick'] == '1'),
        ),
      ),
      GoRoute(
        path: '/food/new',
        builder: (context, state) => IngredientFoodRouteExtra.wrapRoute(
          state.extra,
          FoodEditorScreen(
            initialDraft: IngredientFoodRouteExtra.draftFrom(state.extra),
          ),
        ),
      ),
      GoRoute(
        path: '/food/:id',
        builder: (context, state) => IngredientFoodRouteExtra.wrapRoute(
          state.extra,
          FoodEditorScreen(
            foodId: state.pathParameters['id'],
            initialLabel: IngredientFoodRouteExtra.labelFrom(state.extra),
          ),
        ),
      ),
    ],
  );
  addTearDown(harness.router.dispose);
  addTearDown(harness.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: HearthTheme.light(),
        darkTheme: HearthTheme.dark(),
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        routerConfig: harness.router,
      ),
    ),
  );
  await tester.tap(find.text('Review ingredients'));
  await pumpFrames(tester, frames: 20);
  return harness;
}

Future<void> resolutionTap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    final picker = find.byKey(const Key('ingredient-food-picker-scroll'));
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find
          .descendant(of: picker, matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await pumpFrames(tester, frames: 20);
}

/// A painted test surface with a running scanner controller. No native camera,
/// permission request, or platform channel is involved.
class ResolutionScanner extends MobileScannerPlatform {
  bool unavailable = false;
  int starts = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(
    key: Key('synthetic-camera-preview'),
    color: Color(0xff26312c),
  );
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (unavailable) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {}
}

ResolutionScanner useResolutionScanner() {
  final original = MobileScannerPlatform.instance;
  final scanner = ResolutionScanner();
  MobileScannerPlatform.instance = scanner;
  addTearDown(() => MobileScannerPlatform.instance = original);
  return scanner;
}
