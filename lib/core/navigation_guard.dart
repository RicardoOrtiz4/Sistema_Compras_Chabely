import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

class NavigationUnlockObserver extends NavigatorObserver {}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

final Set<String> _activePdfNavigationKeys = <String>{};
const Duration _pdfNavigationCooldown = Duration(milliseconds: 1200);

Future<T?> runGuardedPdfNavigation<T>(
  String key,
  Future<T?> Function() action,
) {
  if (_activePdfNavigationKeys.contains(key)) {
    return Future<T?>.value(null);
  }
  _activePdfNavigationKeys.add(key);
  Timer(_pdfNavigationCooldown, () {
    _activePdfNavigationKeys.remove(key);
  });
  try {
    return action();
  } catch (_) {
    _activePdfNavigationKeys.remove(key);
    rethrow;
  }
}

Future<T?> guardedPush<T>(BuildContext context, String location) {
  return context.push<T>(location);
}

Future<T?> guardedPdfPush<T>(BuildContext context, String location) {
  return runGuardedPdfNavigation<T>(
    'push:$location',
    () => context.push<T>(location),
  );
}

void guardedGo(BuildContext context, String location) {
  context.go(location);
}

void guardedPdfGo(BuildContext context, String location) {
  final key = 'go:$location';
  if (_activePdfNavigationKeys.contains(key)) {
    return;
  }
  _activePdfNavigationKeys.add(key);
  context.go(location);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Timer(_pdfNavigationCooldown, () {
      _activePdfNavigationKeys.remove(key);
    });
  });
}
