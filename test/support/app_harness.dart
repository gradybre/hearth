import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/app/providers.dart';
import 'package:hearth/data/local/hearth_database.dart';
import 'package:hearth/domain/models/recipe.dart';
import 'package:hearth/main.dart';

/// Pumps the real app for a widget test.
///
/// Two overrides, both load-bearing:
///
///  * [databaseProvider] gets an in-memory database. Without it a widget test
///    would open the on-disk database the app itself uses, so tests would
///    share state with each other and with the developer's own library.
///  * [recipeLibraryProvider] is fed a plain stream of [recipes]. Widget tests
///    run under fake async, which cannot drive real sqlite I/O, so a
///    DB-backed stream would never emit — leaving the loading spinner on
///    screen and its animation timer pending at teardown. Feeding the data
///    directly keeps these tests about the UI, deterministic, and fast.
///
/// Repository behaviour is covered against a real database in the data-layer
/// tests, which are the right place for it.
Future<HearthDatabase> pumpHearthApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  List<Recipe> recipes = const <Recipe>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final HearthDatabase db = HearthDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      // Types left to inference: flutter_riverpod 3 does not export the
      // `Override` type name, only the methods that produce one.
      overrides: [
        databaseProvider.overrideWithValue(db),
        recipeLibraryProvider.overrideWith(
          (Ref ref) => Stream<List<Recipe>>.value(recipes),
        ),
      ],
      child: const HearthApp(),
    ),
  );
  await tester.pump();
  return db;
}
