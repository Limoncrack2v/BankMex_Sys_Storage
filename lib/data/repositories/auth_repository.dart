import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_environment.dart';
import '../firestore_cache.dart';
import '../models/app_user.dart';
import '../models/family.dart';
import '../models/staff_request.dart';
import '../plan_reminder.dart';
import 'device_token_repository.dart';
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
  /// [planReminder] es para las pruebas.
  AuthRepository({PlanReminder? planReminder})
    : _planReminder = planReminder ?? PlanReminder.instance;

  /// Mínimo de caracteres de cualquier contraseña nueva: la del Registro de
  /// Staff y la de las cuentas que crea el staff. Firebase solo exige 6.
  static const minPasswordLength = 8;

  static const _weakPasswordMessage =
      'La contraseña debe tener al menos $minPasswordLength caracteres.';

  static const _noAccessMessage =
      'No se pudo iniciar sesión. Contacta a tu centro de BAMX para más '
      'información.';
  static const _offlineMessage =
      'Sin conexión. Revisa tu internet e intenta de nuevo.';

  // late: se toma al usarlo, así las pruebas pueden crear el repositorio sin
  // Firebase (las validaciones de contraseña fallan antes de tocarlo).
  late final _auth = FirebaseAuth.instance;
  final PlanReminder _planReminder;

  /// Lanza [AuthException] si [password] es más corta que
  /// [minPasswordLength]. Las pantallas ya no dejan enviarla; esto cubre a
  /// cualquier otro llamador, porque Firebase acepta desde 6.
  static void _checkPasswordLength(String password) {
    if (password.length < minPasswordLength) {
      throw AuthException(_weakPasswordMessage);
    }
  }

  User? get currentUser => _auth.currentUser;

  /// Usuario de la sesión guardada. En web Firebase la carga de forma
  /// asíncrona, así que currentUser puede ser null justo al abrir la app
  /// aunque haya sesión; el primer evento de authStateChanges llega cuando
  /// ya terminó de cargarla.
  Future<User?> restoredUser() => _auth.authStateChanges().first;

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

  /// Carga el perfil (users/{uid}) y, si es familia, su hogar.
  /// El staff y el nutriólogo son roles válidos sin hogar. Si la cuenta
  /// no tiene perfil válido (o no se puede leer) cierra la sesión con
  /// [signOut] y lanza [AuthException]; si no tiene perfil porque su
  /// solicitud de staff sigue pendiente o se rechazó, el mensaje lo dice.
  Future<AuthSession> resolveSession(User user) async {
    StaffRequest? staffRequest;
    try {
      final profile = await UserRepository().getUserProfile(user.uid);

      if (profile?.role == AppUser.roleStaff ||
          profile?.role == AppUser.roleNutritionist) {
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
      await signOut();
      throw AuthException('No se pudo iniciar sesión. Intenta de nuevo.');
    }

    await signOut();
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

  /// Cancela el recordatorio del plan (también sin conexión), borra el token
  /// de notificaciones de este teléfono, cierra la sesión y borra la caché
  /// local de Firestore (ver signOutAndClearCache).
  Future<void> signOut() async {
    await _planReminder.cancelAll();
    final uid = _auth.currentUser?.uid;
    if (uid != null) await DeviceTokenRepository.instance.unregister(uid);
    await signOutAndClearCache(
      auth: _auth,
      firestore: FirebaseFirestore.instance,
    );
  }

  /// Antigüedad máxima del inicio de sesión para hacer una acción sensible
  /// sin volver a pedir la contraseña. La regla (recentlySignedIn en
  /// firestore.rules) permite 5 minutos; el minuto de diferencia cubre el
  /// desfase del reloj del dispositivo y lo que tarda la escritura.
  static const stepUpWindow = Duration(minutes: 4);

  /// Si [authTime] (el inicio de sesión) está dentro de [stepUpWindow]. Una
  /// diferencia negativa (reloj del dispositivo atrasado) cuenta como
  /// reciente: la regla decide con la hora del servidor.
  static bool isRecentSignIn(DateTime? authTime, {required DateTime now}) =>
      authTime != null && now.difference(authTime) < stepUpWindow;

  /// Si la sesión actual es lo bastante reciente para una acción sensible.
  /// Lee el token que ya se tiene, sin forzar que se renueve (renovarlo no
  /// cambia auth_time).
  Future<bool> hasRecentSignIn() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      final token = await user.getIdTokenResult();
      return isRecentSignIn(token.authTime, now: DateTime.now());
    } catch (_) {
      return false;
    }
  }

  /// Lo que se muestra cuando las reglas niegan una acción sensible porque el
  /// inicio de sesión ya no es reciente: el siguiente toque pide la
  /// contraseña (ensureRecentSignIn).
  static const staleSignInMessage =
      'Tu sesión necesita confirmarse. Intenta de nuevo.';

  /// [staleSignInMessage] si [error] es un permission-denied y la sesión no
  /// es reciente; si no, null y cada pantalla muestra su propio mensaje.
  static String? staleSignInMessageFor(
    Object error, {
    required bool recentSignIn,
  }) => !recentSignIn && _isPermissionDenied(error) ? staleSignInMessage : null;

  /// [staleSignInMessageFor] con la sesión actual. Solo para acciones que
  /// piden una sesión reciente (las que pasan por ensureRecentSignIn).
  Future<String?> staleSignInError(Object error) async =>
      _isPermissionDenied(error)
      ? staleSignInMessageFor(error, recentSignIn: await hasRecentSignIn())
      : null;

  static bool _isPermissionDenied(Object error) =>
      error is FirebaseException && error.code == 'permission-denied';

  /// Confirma la identidad de quien tiene la sesión con su contraseña; el
  /// token nuevo trae un auth_time reciente. Lanza [AuthException].
  Future<void> reauthenticate(String password) async {
    const failed = 'No se pudo confirmar tu identidad. Intenta de nuevo.';
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw AuthException(failed);
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'wrong-password' ||
        'invalid-credential' => 'Contraseña incorrecta. Intenta de nuevo.',
        'too-many-requests' =>
          'Demasiados intentos. Espera un momento e intenta de nuevo.',
        'network-request-failed' => _offlineMessage,
        _ => failed,
      });
    }
    // Da tiempo a que Firestore tome el token nuevo (nunca getIdToken(true)).
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

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
    _checkPasswordLength(password);

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
        'weak-password' => _weakPasswordMessage,
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
      // Sin borrar la caché (ver signOut): esta cuenta no llegó a entrar a la
      // app y solo escribió su propia solicitud.
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
  ///
  /// [appliances] son ids de [Appliance]; solo se usan para familias.
  Future<Family?> registerAccount({
    required String role,
    required String name,
    required String email,
    required String password,
    String? address,
    List<String> appliances = const [],
  }) async {
    _checkPasswordLength(password);

    final appliancesError = Family.validateAppliances(appliances);
    if (appliancesError != null) throw ArgumentError(appliancesError);

    final app = await Firebase.initializeApp(
      name: 'registro-${DateTime.now().microsecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    final auth = FirebaseAuth.instanceFor(app: app);

    try {
      await connectToEmulatorsIfDebug(auth: auth);

      if (kIsWeb) await auth.setPersistence(Persistence.NONE);

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
          'weak-password' => _weakPasswordMessage,
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
          recoveryQuotaDefault: Family.standardRecoveryQuota,
          authUid: newUser.uid,
          appliances: appliances,
        );
        batch.set(
          db.collection('families').doc(newUser.uid),
          family.toFirestore(),
        );
      }

      try {
        await batch.commit();
      } catch (e) {
        try {
          await newUser.delete();
        } catch (_) {
          // Sin conexión no se puede borrar; la cuenta queda sin perfil y no
          // puede entrar a la app.
        }
        throw AuthException(
          await staleSignInError(e) ??
              'No se pudo crear la cuenta. Intenta de nuevo.',
        );
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
