import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:sistema_compras/features/orders/data/order_local_snapshot_store.dart';
import 'firebase_options.dart';
import 'package:sistema_compras/app/app.dart';
import 'package:sistema_compras/core/app_logger.dart';
import 'package:sistema_compras/core/error_reporter.dart';
import 'package:sistema_compras/core/startup_endpoint_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init(maxEntries: 1000);
  FlutterError.onError = (details) {
    logError(details.exception, details.stack, context: 'FlutterError');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError(error, stack, context: 'PlatformDispatcher');
    return true;
  };
  await runZonedGuarded(() async {
    AppLogger.log('main startup begin', tag: 'BOOT');
    await initializeDateFormatting('es_MX');
    AppLogger.log('date formatting initialized', tag: 'BOOT');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.log('firebase initialized', tag: 'BOOT');
    assertNoLocalhostEndpoints(Firebase.app().options);
    await OrderLocalSnapshotStore.ensureInitialized();
    AppLogger.log('local snapshot store initialized', tag: 'BOOT');
    runApp(const ProviderScope(child: SistemaComprasApp()));
    AppLogger.log('runApp completed', tag: 'BOOT');
  }, (error, stack) {
    logError(error, stack, context: 'runZonedGuarded');
  });
}
