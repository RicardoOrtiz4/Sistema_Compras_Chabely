import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/features/orders/data/order_local_snapshot_store.dart';
import 'firebase_options.dart';
import 'package:sistema_compras/app/app.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/startup_endpoint_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  assertNoLocalhostEndpoints(Firebase.app().options);
  await OrderLocalSnapshotStore.ensureInitialized();

  FlutterError.onError = (details) {
    logError(details.exception, details.stack, context: 'FlutterError');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError(error, stack, context: 'PlatformDispatcher');
    return true;
  };

  runApp(const ProviderScope(child: SistemaComprasApp()));
}
