import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dart:io';

import 'firebase_options.dart';
import 'data/models/family.dart';
import 'data/models/pantry_item.dart';
import 'data/repositories/family_repository.dart';
import 'data/repositories/pantry_repository.dart';
import 'data/models/app_user.dart';
import 'data/repositories/user_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kDebugMode) {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseAuth.instance.useAuthEmulator(host, 9099);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  String _crudStatus = '';
  String _loginOrSignInStatus = '';
  String? _familyId, _pantryItemId;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Future<void> _testCreate() async {
    setState(() => _crudStatus = 'Creando familia y item...');

    try {
      final familyRepo = FamilyRepository();
      final pantryRepo = PantryRepository();
      final userCred = await FirebaseAuth.instance.signInAnonymously();
      final uid = userCred.user!.uid;

      final familyId = await familyRepo.createFamily(
        Family(
          familyId: '',
          address: 'Calle XYZ 123',
          registrationDate: DateTime.now(),
          authUid: uid,
          appliances: ['refrigerador'],
        ),
      );

      final itemId = await pantryRepo.createPantryItem(
        familyId,
        PantryItem(
          pantryItemId: '',
          productId: 'arroz-1kg',
          deliveryId: 'entrega-001',
          type: FoodType.grain,
          quantity: 3,
          unit: FoodUnit.kg,
          daysUntilExpiration: 30,
          synchronized: true,
          deviceId: 'device-test',
          localTimestamp: DateTime.now(),
        ),
      );

      final fetched = await pantryRepo.getPantryItem(familyId, itemId);

      setState(() {
        _crudStatus =
            'OK -> familyId: $familyId, itemId: $itemId, producto leído: ${fetched?.productId} (x${fetched?.quantity})';
        _familyId = familyId;
        _pantryItemId = itemId;
      });
    } catch (e) {
      setState(() => _crudStatus = 'Error: $e');
    }
  }

  Future<void> _testRegisterDelivery() async {
    setState(() => _crudStatus = 'Registrando entrega...');

    try {
      final familyRepo = FamilyRepository();
      final pantryRepo = PantryRepository();
      final userCred = await FirebaseAuth.instance.signInAnonymously();

      final familyId = await familyRepo.createFamily(
        Family(
          familyId: '',
          address: 'Calle XYZ 123',
          registrationDate: DateTime.now(),
          authUid: userCred.user!.uid,
          appliances: ['refrigerador'],
        ),
      );

      PantryItem item(String productId, FoodType type, double qty, FoodUnit unit) =>
          PantryItem(
            pantryItemId: '',
            productId: productId,
            deliveryId: '',
            type: type,
            quantity: qty,
            unit: unit,
            daysUntilExpiration: 30,
            synchronized: true,
            deviceId: 'device-test',
            localTimestamp: DateTime.now(),
          );

      final deliveryId = await pantryRepo.registerDelivery(familyId, [
        item('arroz', FoodType.grain, 2.5, FoodUnit.kg),
        item('leche', FoodType.dairy, 6, FoodUnit.l),
        item('atun', FoodType.canned, 12, FoodUnit.can),
      ]);

      final items = await pantryRepo.watchAllPantryItems(familyId).first;

      setState(() {
        _crudStatus =
            'OK -> entrega: $deliveryId, ${items.length} productos registrados';
        _familyId = familyId;
      });
    } catch (e) {
      setState(() => _crudStatus = 'Error: $e');
    }
  }

  Future<void> _testUpdate() async {
    if (_familyId == null || _pantryItemId == null) {
      setState(() => _crudStatus = 'Primero crea un registro');
      return;
    }

    setState(() => _crudStatus = 'Actualizando item de la familia');

    try {
      final pantryRepo = PantryRepository();
      final changes = {'quantity': 2};

      await pantryRepo.updatePantryItem(_familyId!, _pantryItemId!, changes);

      final fetched = await pantryRepo.getPantryItem(
        _familyId!,
        _pantryItemId!,
      );

      setState(() {
        _crudStatus =
            'OK -> itemId: $_pantryItemId, producto leído: ${fetched?.productId} (x${fetched?.quantity})';
      });
    } catch (e) {
      setState(() => _crudStatus = 'Error: $e');
    }
  }

  Future<void> _testDelete() async {
    if (_familyId == null || _pantryItemId == null) {
      setState(() => _crudStatus = 'No hay un item que eliminar');
      return;
    }

    setState(() => _crudStatus = 'Eliminando item de la familia');

    try {
      final pantryRepo = PantryRepository();

      await pantryRepo.deletePantryItem(_familyId!, _pantryItemId!);

      final fetched = await pantryRepo.getPantryItem(
        _familyId!,
        _pantryItemId!,
      );

      setState(() {
        if (fetched == null) {
          _crudStatus = 'OK -> item eliminado';
          _pantryItemId = null;
        } else {
          _crudStatus = 'Error: el item no fue eliminado';
        }
      });
    } catch (e) {
      setState(() => _crudStatus = 'Error: $e');
    }
  }

  Future<void> _testUnauthorizedCreate() async {
    setState(() => _crudStatus = 'Probando creación sin sesión');

    await FirebaseAuth.instance.signOut();

    try {
      final familyRepo = FamilyRepository();

      await familyRepo.createFamily(
        Family(
          familyId: '',
          address: 'Calle 123',
          registrationDate: DateTime.now(),
          authUid: 'uid',
          appliances: [],
        ),
      );

      setState(() => _crudStatus = 'Falló la creación de la familia');
    } catch (e) {
      setState(() => _crudStatus = 'Se bloqueó correctamente');
    }
  }

  Future<void> _signUpStaff(String name, String email, String password) async {
    setState(() => _crudStatus = '');

    try {
      final userRepo = UserRepository();
      final userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final uid = userCred.user!.uid;

      try {
        await userRepo.createUserProfile(
          AppUser(
            userId: uid,
            name: name,
            email: email,
            role: 'staff',
            createdAt: DateTime.now(),
          ),
        );
      } catch (e) {
        await userCred.user!.delete();
        setState(
          () => _loginOrSignInStatus =
              'Error creando tu usuario. Intenta de nuevo',
        );
        return;
      }

      setState(() => _loginOrSignInStatus = 'Usuario creado con éxito');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        setState(
          () => _loginOrSignInStatus =
              'Ya existe una cuenta con este correo electrónico',
        );
      } else if (e.code == 'weak-password') {
        setState(() => _loginOrSignInStatus = 'La contraseña es muy débil');
      }
    } catch (e) {
      setState(() => _loginOrSignInStatus = 'Error: $e');
    }
  }

  Future<void> _loginStaff(String email, String password) async {
    setState(() => _crudStatus = '');

    try {
      final userRepo = UserRepository();
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCred.user!.uid;

      final AppUser? user = await userRepo.getUserProfile(uid);

      if (user == null) {
        setState(
          () => _loginOrSignInStatus = 'No se pudo iniciar sesión. Contacta a tu centro de BAMX para más información',
        );
      } else {
        setState(
          () => _loginOrSignInStatus = 'Sesión iniciada como ${user.role}',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' ||
          e.code == 'user-not-found' ||
          e.code == 'wrong-password') {
        setState(
          () => _loginOrSignInStatus =
              'Correo o contraseña inválidos. Intenta de nuevo',
        );
      }
    } catch (e) {
      setState(() => _loginOrSignInStatus = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _testCreate,
              child: const Text('Probar Create'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _testRegisterDelivery,
              child: const Text('Probar registro de entrega'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _pantryItemId != null ? _testUpdate : null,
              child: const Text('Probar Update'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _pantryItemId != null ? _testDelete : null,
              child: const Text('Probar Delete'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _testUnauthorizedCreate,
              child: const Text('Probar Create sin sesión'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _signUpStaff(
                  'Staff de prueba',
                  'staff@example.com',
                  'password123',
                );
              },
              child: const Text('Registrar staff'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loginStaff('staff@example.com', 'password123');
              },
              child: const Text('Iniciar sesión Staff'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loginStaff('staff@example.com', '123456');
              },
              child: const Text('Iniciar sesión Staff (credenciales inválidas)'),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                height: 48,
                child: Text(
                  _crudStatus.isNotEmpty ? _crudStatus : _loginOrSignInStatus,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
