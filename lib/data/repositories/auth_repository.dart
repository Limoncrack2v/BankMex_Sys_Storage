import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_environment.dart';
import '../models/app_user.dart';
import '../models/family.dart';
import 'family_repository.dart';
import 'user_repository.dart';

/// Usuario con sesión iniciada. Las cuentas de familia traen su hogar.
class AuthSession {
  AuthSession({required this.user, this.family});

  final AppUser user;
  final Family? family;

  bool get isStaff => user.role == AppUser.roleStaff;
}

/// Error de autenticación con un mensaje listo para mostrar al usuario.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  static const _noAccessMessage =
      'No se pudo iniciar sesión. Contacta a tu centro de BAMX para más '
      'información.';
  static const _offlineMessage =
      'Sin conexión. Revisa tu internet e intenta de nuevo.';

  final _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Future<AuthSession> signIn(String email, String password) async {
    final UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'invalid-credential' ||
        'invalid-email' ||
        'user-not-found' ||
        'wrong-password' => 'Correo o contraseña inválidos. Intenta de nuevo.',
        'user-disabled' => _noAccessMessage,
        'too-many-requests' =>
          'Demasiados intentos. Espera un momento e intenta de nuevo.',
        'network-request-failed' => _offlineMessage,
        _ => 'No se pudo iniciar sesión. Intenta de nuevo.',
      });
    }
    return resolveSession(credential.user!);
  }

  /// Carga el perfil (users/{uid}) y, si es familia, su hogar. Si la cuenta
  /// no tiene perfil válido (o no se puede leer) cierra la sesión y lanza
  /// [AuthException].
  Future<AuthSession> resolveSession(User user) async {
    try {
      final profile = await UserRepository().getUserProfile(user.uid);

      if (profile?.role == AppUser.roleStaff) {
        return AuthSession(user: profile!);
      }
      if (profile?.role == AppUser.roleFamily) {
        final family = await FamilyRepository().getFamilyByAuthUid(user.uid);
        if (family != null) return AuthSession(user: profile!, family: family);
      }
    } catch (_) {
      await _auth.signOut();
      throw AuthException('No se pudo iniciar sesión. Intenta de nuevo.');
    }

    await _auth.signOut();
    throw AuthException(_noAccessMessage);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'invalid-email' || 'missing-email' => 'Ingresa un correo válido.',
        'network-request-failed' => _offlineMessage,
        _ => 'No se pudo enviar el correo. Intenta de nuevo.',
      });
    }
  }

  /// Crea una cuenta nueva (Auth + users/{uid}) y, para familias, su hogar en
  /// families/{uid}. Solo la usa el staff con sesión iniciada:
  /// - La cuenta de Auth se crea en una instancia secundaria de Firebase para
  ///   no cerrar la sesión del staff.
  /// - El perfil y el hogar los escribe el staff en un solo batch, así nunca
  ///   queda uno sin el otro. Si el batch falla se borra la cuenta de Auth.
  Future<Family?> registerAccount({
    required String role,
    required String name,
    required String email,
    required String password,
    String? address,
  }) async {
    final app = await Firebase.initializeApp(
      name: 'registro-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final auth = FirebaseAuth.instanceFor(app: app);

    try {
      await connectToEmulatorsIfDebug(auth: auth);

      final UserCredential credential;
      try {
        credential = await auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        throw AuthException(switch (e.code) {
          'email-already-in-use' =>
            'Ya existe una cuenta con este correo electrónico.',
          'invalid-email' => 'Ingresa un correo válido.',
          'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
          'network-request-failed' => _offlineMessage,
          _ => 'No se pudo crear la cuenta. Intenta de nuevo.',
        });
      }

      final newUser = credential.user!;
      final now = DateTime.now();
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      batch.set(
        db.collection('users').doc(newUser.uid),
        AppUser(
          userId: newUser.uid,
          name: name.trim(),
          email: email.trim(),
          role: role,
          createdAt: now,
        ).toFirestore(),
      );

      Family? family;
      if (role == AppUser.roleFamily) {
        family = Family(
          familyId: newUser.uid,
          name: name.trim(),
          address: (address ?? '').trim(),
          registrationDate: now,
          authUid: newUser.uid,
          appliances: const [],
        );
        batch.set(
          db.collection('families').doc(newUser.uid),
          family.toFirestore(),
        );
      }

      try {
        await batch.commit();
      } catch (_) {
        try {
          await newUser.delete();
        } catch (_) {
          // Sin conexión no se puede borrar; la cuenta queda sin perfil y no
          // puede entrar a la app.
        }
        throw AuthException('No se pudo crear la cuenta. Intenta de nuevo.');
      }
      return family;
    } finally {
      try {
        await auth.signOut();
      } finally {
        await app.delete();
      }
    }
  }
}
