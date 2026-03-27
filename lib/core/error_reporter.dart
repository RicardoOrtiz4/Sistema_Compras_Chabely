import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AppError {
  const AppError(this.message, {this.cause, this.stack});

  final String message;
  final Object? cause;
  final StackTrace? stack;
}

String reportError(
  Object error,
  StackTrace? stack, {
  String? context,
}) {
  if (error is AppError) {
    final cause = error.cause;
    final nextStack = error.stack;

    if (cause != null) {
      logError(cause, nextStack, context: context);
    } else {
      logError(error, nextStack, context: context);
    }

    return error.message;
  }

  logError(error, stack, context: context);
  return userMessage(error);
}


void logError(
  Object error,
  StackTrace? stack, {
  String? context,
}) {
  final buffer = StringBuffer('ERROR');
  if (context != null && context.isNotEmpty) {
    buffer.write(' [$context]');
  }
  buffer.write(': ${error.runtimeType}');
  if (error is FirebaseException) {
    buffer.write(' code=${error.code}');
    if (error.message != null && error.message!.isNotEmpty) {
      buffer.write(' message=${error.message}');
    } else {
      buffer.write(' message=$error');
    }
  } else if (error is StateError) {
    buffer.write(' message=${error.message}');
  } else {
    buffer.write(' message=$error');
  }
  debugPrint(buffer.toString());
  if (error is FirebaseFunctionsException && error.details != null) {
    debugPrint('ERROR details: ${error.details}');
  }
  if (stack != null) {
    debugPrint(stack.toString());
  }
}

String userMessage(Object error) {
  if (error is String) {
    return error;
  }
  if (error is FirebaseAuthException) {
    return _authMessage(error);
  }
  if (error is FirebaseFunctionsException) {
    return _functionsMessage(error);
  }
  if (error is FirebaseException) {
    if (error.plugin == 'firebase_database') {
      return _databaseMessage(error);
    }
    return _firebaseMessage(error);
  }
  if (error is StateError) {
    return error.message;
  }
  return 'Ocurrio un error inesperado. Intenta de nuevo.';
}

String _authMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'El correo no tiene un formato valido.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Correo o contrasena incorrectos.';
    case 'user-disabled':
      return 'Tu cuenta esta desactivada. Contacta al administrador.';
    case 'too-many-requests':
      return 'Demasiados intentos. Intenta mas tarde.';
    case 'network-request-failed':
      return 'Sin conexion. Revisa tu red e intenta de nuevo.';
    default:
      return 'No se pudo iniciar sesion. Intenta de nuevo.';
  }
}

String _functionsMessage(FirebaseFunctionsException error) {
  switch (error.code) {
    case 'unauthenticated':
      return 'Debes iniciar sesion para continuar.';
    case 'permission-denied':
      return 'No tienes permisos para esta accion.';
    case 'invalid-argument':
      return 'Faltan datos requeridos. Revisa la informacion.';
    case 'failed-precondition':
      return 'No se puede completar la accion. Verifica los datos.';
    case 'not-found':
      return 'No se encontro la informacion solicitada.';
    case 'unavailable':
      return 'Servicio no disponible. Intenta mas tarde.';
    default:
      return 'No se pudo completar la operacion. Intenta de nuevo.';
  }
}

String _databaseMessage(FirebaseException error) {
  switch (error.code) {
    case 'permission-denied':
      return 'No tienes permisos para esta accion.';
    case 'network-error':
      return 'Sin conexion. Revisa tu red e intenta de nuevo.';
    default:
      return 'No se pudo acceder a la base de datos.';
  }
}

String _firebaseMessage(FirebaseException error) {
  if (error.code == 'permission-denied') {
    return 'No tienes permisos para esta accion.';
  }
  if (error.code == 'network-request-failed') {
    return 'Sin conexion. Revisa tu red e intenta de nuevo.';
  }
  return 'Ocurrio un error al comunicarse con el servidor.';
}
