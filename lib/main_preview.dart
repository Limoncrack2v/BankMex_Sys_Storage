import 'package:flutter/material.dart';

import 'ui/screens/home/home_screen.dart';
import 'ui/theme/app_theme.dart';

/// Vista previa de la UI sin Firebase, con los datos de ejemplo del Figma.
/// Uso: flutter run -t lib/main_preview.dart
void main() {
  runApp(
    MaterialApp(
      title: 'BAMX Guadalajara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      home: const HomeScreen(),
    ),
  );
}
