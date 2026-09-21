import 'package:flutter/material.dart';

/// Para acciones del diseño que todavía no tienen pantalla.
void showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Disponible próximamente')));
}
