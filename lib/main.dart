import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sistema_compras/core/app_logger.dart';
import 'firebase_options.dart';
import 'package:sistema_compras/app/app.dart';
import 'package:sistema_compras/core/error_reporter.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.init();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (_supportsBackgroundMessaging()) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  FlutterError.onError = (details) {
    logError(details.exception, details.stack, context: 'FlutterError');
    if (kDebugMode) {
      AppLogger.dumpToConsole(reason: 'FlutterError');
    }
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError(error, stack, context: 'PlatformDispatcher');
    if (kDebugMode) {
      AppLogger.dumpToConsole(reason: 'PlatformDispatcher');
    }
    return true;
  };

  runApp(const ProviderScope(child: SistemaComprasApp()));
}

bool _supportsBackgroundMessaging() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}
