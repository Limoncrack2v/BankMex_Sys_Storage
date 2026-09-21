import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'data/firebase_environment.dart';
import 'ui/screens/session/session_gate.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await connectToEmulatorsIfDebug(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BAMX Guadalajara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      locale: AppTheme.locale,
      supportedLocales: const [AppTheme.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const SessionGate(),
    );
  }
}
