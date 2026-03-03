import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

class NavigationUnlockObserver extends NavigatorObserver {}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

Future<T?> guardedPush<T>(BuildContext context, String location) {
  return context.push<T>(location);
}

void guardedGo(BuildContext context, String location) {
  context.go(location);
}
