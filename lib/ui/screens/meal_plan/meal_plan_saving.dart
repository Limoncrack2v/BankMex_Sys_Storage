import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../../data/models/member.dart';
import '../../../domain/models/meal_plan.dart';
import '../../models/recipe.dart';

// Lo que comparten las vistas que escriben el plan guardado de la familia
// (mealPlans/{id}): qué porciones se guardan y cómo se espera al servidor.

/// Sin conexión, Firestore aplica el cambio en el dispositivo (el plan se
/// actualiza al instante) pero la escritura no termina hasta volver a estar
/// en línea. Pasado este tiempo se da por guardada y se sincroniza después.
const _saveTimeout = Duration(seconds: 4);
const _pendingSyncNote = 'Se sincronizará cuando haya conexión.';

/// Porciones que se guardan para [recipe] en una comida del plan: las que come
/// el hogar ([householdPortions]) con 2 decimales. Sin integrantes
/// registrados son las de la receta, porque una comida no se guarda con 0
/// porciones, y nunca pasan de [MealPlanMeal.maxServings].
double planServings(List<Member> members, Recipe recipe) {
  final portions = (householdPortions(members) * 100).round() / 100;
  final servings = portions > 0 ? portions : recipe.servings.toDouble();
  return servings > 0 ? math.min(servings, MealPlanMeal.maxServings) : 1;
}

/// Espera [write] hasta 4 segundos. Regresa false si se agotó el tiempo: el
/// cambio ya está en el dispositivo y se sincroniza al volver la conexión. Si
/// después el servidor lo rechaza, llama a [onLateError].
Future<bool> awaitPlanWrite<T>(
  Future<T> write, {
  required VoidCallback onLateError,
}) async {
  try {
    await write.timeout(_saveTimeout);
    return true;
  } on TimeoutException {
    unawaited(write.then<void>((_) {}, onError: (Object _) => onLateError()));
    return false;
  }
}

/// [message] con la nota de sincronización si el cambio sigue pendiente.
String withSyncNote(String message, {required bool synced}) =>
    synced ? message : '$message $_pendingSyncNote';

/// Qué decir cuando no se pudo escribir el plan: el motivo de un
/// ArgumentError (p. ej. de [MealPlan.validate]) o [fallback].
String planWriteError(Object error, String fallback) {
  if (error is ArgumentError && error.message is String) {
    final message = error.message as String;
    return RegExp(r'[.?!]$').hasMatch(message) ? message : '$message.';
  }
  if (error is FirebaseException && error.code == 'not-found') {
    return 'Este plan ya no existe. Puede que se haya eliminado en otro '
        'dispositivo.';
  }
  return fallback;
}

void showPlanSnack(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
