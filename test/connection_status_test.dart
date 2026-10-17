import 'dart:async';

import 'package:bank_storage_app/ui/connection_status.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final status = ConnectionStatus.instance;
  late StreamController<bool> fromCache;
  late StreamController<List<ConnectivityResult>> network;

  // Dentro de cada prueba, para que los streams corran en su reloj falso.
  void start() {
    fromCache = StreamController<bool>();
    network = StreamController<List<ConnectivityResult>>();
    status.listen(fromCache: fromCache.stream, network: network.stream);
  }

  tearDown(status.stop);

  testWidgets('airplane mode is offline at once, before Firestore notices', (
    tester,
  ) async {
    start();
    fromCache.add(false);
    network.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(status.online.value, isTrue);

    network.add([ConnectivityResult.none]);
    await tester.pump();
    expect(status.online.value, isFalse);
  });

  testWidgets('back on the network, online again if Firestore never noticed', (
    tester,
  ) async {
    start();
    fromCache.add(false);
    network.add([ConnectivityResult.none]);
    await tester.pump();
    expect(status.online.value, isFalse);

    network.add([ConnectivityResult.mobile]);
    await tester.pump();
    expect(status.online.value, isTrue);
  });

  testWidgets(
    'back on the network, waits for Firestore if it served the cache',
    (tester) async {
      start();
      network.add([ConnectivityResult.none]);
      fromCache.add(true);
      await tester.pump(const Duration(seconds: 3));
      expect(status.online.value, isFalse);

      network.add([ConnectivityResult.wifi]);
      await tester.pump(const Duration(seconds: 3));
      expect(status.online.value, isFalse);

      fromCache.add(false);
      await tester.pump();
      expect(status.online.value, isTrue);
    },
  );

  testWidgets('with network, the cache alone waits 3 s before going offline', (
    tester,
  ) async {
    start();
    network.add([ConnectivityResult.wifi]);
    fromCache.add(true);
    await tester.pump(const Duration(seconds: 2));
    expect(status.online.value, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(status.online.value, isFalse);
  });
}
