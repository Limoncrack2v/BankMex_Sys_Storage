import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../session_navigation.dart';
import '../../theme/app_colors.dart';
import '../sign_in/sign_in_screen.dart';

/// Primera pantalla: si ya hay sesión la retoma según el rol; si no (o si la
/// cuenta ya no es válida), muestra el inicio de sesión.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key, this.restoreUser, this.resolveSession});

  /// Solo para pruebas; por defecto AuthRepository.restoredUser.
  final Future<User?> Function()? restoreUser;

  /// Solo para pruebas; por defecto AuthRepository.resolveSession.
  final Future<AuthSession> Function(User user)? resolveSession;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  bool _showSignIn = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final restore = widget.restoreUser ?? AuthRepository().restoredUser;
    final user = await restore();
    if (!mounted) return;

    if (user == null) {
      setState(() => _showSignIn = true);
      return;
    }

    final resolve = widget.resolveSession ?? AuthRepository().resolveSession;

    try {
      final session = await resolve(user);
      if (!mounted) return;
      openSessionHome(context, session);
    } catch (_) {
      if (mounted) setState(() => _showSignIn = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSignIn) return const SignInScreen();

    return const Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}
