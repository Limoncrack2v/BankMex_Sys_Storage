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
          quantity: 3,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_crudStatus, textAlign: TextAlign.center),
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
