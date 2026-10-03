import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/auth/auth_gateway.dart';
import '../../data/repositories/food_repository.dart';

/// One pending food-capture continuation, bound before its first await.
/// An identity or repository change closes it permanently, even after A→B→A.
/// Call [close] in finally; expiration also releases its subscriptions at once.
class FoodCaptureGuard {
  factory FoodCaptureGuard.capture(BuildContext context) =>
      FoodCaptureGuard._(ProviderScope.containerOf(context, listen: false));

  FoodCaptureGuard._(this._container)
    : _user = _container.read(currentUserIdProvider),
      _household = _container.read(currentHouseholdIdProvider),
      _foods = _container.read(foodRepositoryProvider) {
    _subscriptions.add(
      _container.listen<String>(currentUserIdProvider, (before, after) {
        if (after != _user) close();
      }),
    );
    _subscriptions.add(
      _container.listen<String>(currentHouseholdIdProvider, (before, after) {
        if (after != _household) close();
      }),
    );
    _subscriptions.add(
      _container.listen<FoodRepository>(foodRepositoryProvider, (
        before,
        after,
      ) {
        if (!identical(after, _foods)) close();
      }),
    );
    _subscriptions.add(
      _container.listen<AsyncValue<HearthAccount?>>(accountProvider, (
        before,
        after,
      ) {
        if (before?.hasValue == true &&
            after.hasValue &&
            ((before?.value == null) != (after.value == null) ||
                before?.value?.userId != after.value?.userId ||
                before?.value?.householdId != after.value?.householdId)) {
          close();
        }
      }),
    );
  }

  final ProviderContainer _container;
  final String _user;
  final String _household;
  final FoodRepository _foods;
  final List<ProviderSubscription<Object?>> _subscriptions = [];
  bool _closed = false;

  bool canContinue(BuildContext context) {
    if (_closed) return false;
    if (!context.mounted ||
        !identical(
          ProviderScope.containerOf(context, listen: false),
          _container,
        ) ||
        _container.read(currentUserIdProvider) != _user ||
        _container.read(currentHouseholdIdProvider) != _household ||
        !identical(_container.read(foodRepositoryProvider), _foods)) {
      close();
      return false;
    }
    return ModalRoute.of(context)?.isCurrent ?? false;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
  }
}
