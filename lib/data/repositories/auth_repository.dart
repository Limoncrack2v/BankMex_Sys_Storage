import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_environment.dart';
import '../models/app_user.dart';
import '../models/family.dart';
import '../models/staff_request.dart';
import 'family_repository.dart';
import 'staff_request_repository.dart';
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
  /// [AuthException]; si no tiene perfil porque su solicitud de staff sigue
  /// pendiente o se rechazó, el mensaje lo dice.
  Future<AuthSession> resolveSession(User user) async {
    StaffRequest? staffRequest;
    try {
      final profile = await UserRepository().getUserProfile(user.uid);

      if (profile?.role == AppUser.roleStaff) {
        return AuthSession(user: profile!);
      }
      if (profile?.role == AppUser.roleFamily) {
        final family = await FamilyRepository().getFamilyByAuthUid(user.uid);
        if (family != null) return AuthSession(user: profile!, family: family);
      }
      if (profile == null) {
        staffRequest = await StaffRequestRepository().getRequest(user.uid);
      }
    } catch (_) {
      await _auth.signOut();
      throw AuthException('No se pudo iniciar sesión. Intenta de nuevo.');
    }

    await _auth.signOut();
    throw AuthException(switch (staffRequest?.status) {
      StaffRequestStatus.pending =>
        'Tu solicitud de cuenta de staff está pendiente. Podrás iniciar '
            'sesión cuando un staff de BAMX Guadalajara la apruebe.',
      StaffRequestStatus.rejected =>
        'Tu solicitud de cuenta de staff no fue aprobada. Acude a tu centro '
            'de distribución BAMX.',
      StaffRequestStatus.approved || null => _noAccessMessage,
    });
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

  /// "Registro de Staff": crea la cuenta de Auth de la persona y su solicitud
  /// en staffRequests/{uid}. No puede entrar a la app hasta que un staff la
  /// apruebe, así que al terminar siempre se cierra la sesión. Si la
  /// solicitud no se guarda se borra la cuenta de Auth, para que pueda
  /// intentarlo otra vez con el mismo correo.
  Future<void> requestStaffAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'email-already-in-use' =>
          'Ya existe una cuenta con este correo electrónico.',
        'invalid-email' => 'Ingresa un correo válido.',
        'weak-password' => 'La contraseña debe tener al menos 8 caracteres.',
        'network-request-failed' => _offlineMessage,
        _ => _requestFailedMessage,
      });
    }

    final newUser = credential.user!;
    // Si alguien más inició sesión mientras tanto, ya no se toca la sesión:
    // cerrarla o borrar "el usuario actual" sería sobre la otra cuenta.
    bool stillSignedIn() => _auth.currentUser?.uid == newUser.uid;

    try {
      // Las reglas piden el correo tal como lo trae el token de la cuenta.
      final request = StaffRequest(
        uid: newUser.uid,
        name: name,
        email: newUser.email ?? email.trim(),
        status: StaffRequestStatus.pending,
        createdAt: DateTime.now(),
      );
      await FirebaseFirestore.instance
          .collection('staffRequests')
          .doc(newUser.uid)
          .set(request.toFirestore())
          .timeout(const Duration(seconds: 20));

      // Le sirve para demostrar que el correo es suyo cuando el staff revise
      // la solicitud; si falla, la solicitud ya quedó registrada.
      try {
        await newUser.sendEmailVerification();
      } catch (_) {}
    } catch (e) {
      if (stillSignedIn()) {
        try {
          await newUser.delete();
        } catch (_) {
          // Sin conexión no se puede borrar; la cuenta queda sin solicitud ni
          // perfil y no puede entrar a la app.
        }
      }
      throw AuthException(
        e is TimeoutException ? _offlineMessage : _requestFailedMessage,
      );
    } finally {
      if (stillSignedIn()) await _auth.signOut();
    }
  }

  static const _requestFailedMessage =
      'No se pudo enviar tu solicitud. Intenta de nuevo.';

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
