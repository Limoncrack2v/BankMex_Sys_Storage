import 'package:flutter/material.dart';

import '../data/repositories/auth_repository.dart';
import 'connection_status.dart';
import 'screens/home/home_screen.dart';
import 'screens/sign_in/sign_in_screen.dart';
import 'screens/staff/staff_home_screen.dart';

/// Abre la pantalla principal según el rol y borra el historial de rutas.
void openSessionHome(BuildContext context, AuthSession session) {
  final Widget home = session.isStaff
      ? StaffHomeScreen(session: session)
      : HomeScreen(family: session.family!);

  ConnectionStatus.instance.watch(session.user.userId);
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => home),
    (_) => false,
  );
}

/// Regresa al inicio de sesión y después cierra la sesión. En ese orden, las
/// pantallas de la sesión se desmontan antes y sus listeners de Firestore no
/// alcanzan a recibir errores de permiso.
Future<void> signOutAndReturnToSignIn(BuildContext context) async {
  ConnectionStatus.instance.stop();
  // Sin await: el Future de push solo termina cuando se quita la ruta.
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const _SignOutScreen()),
    (_) => false,
  );
}

class _SignOutScreen extends StatefulWidget {
  const _SignOutScreen();

  @override
  State<_SignOutScreen> createState() => _SignOutScreenState();
}

class _SignOutScreenState extends State<_SignOutScreen> {
  bool _signedOut = false;

  @override
  void initState() {
    super.initState();
    // Espera a que termine la transición (y se desmonten las pantallas
    // anteriores) antes de cerrar la sesión.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await AuthRepository().signOut();
      if (mounted) setState(() => _signedOut = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _signedOut
        ? const SignInScreen()
        : const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
