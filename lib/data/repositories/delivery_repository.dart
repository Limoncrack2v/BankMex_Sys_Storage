import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../device_identity.dart';
import '../models/delivery.dart';
import '../models/family.dart';

typedef DeliveryWithSync = ({Delivery delivery, bool pendingSync});

/// Entregas del staff. La app no escribe en la despensa: cuando una entrega
/// queda como entregada, la Cloud Function onDeliveryWritten
/// (functions/index.js) agrega sus productos a families/{familyId}/pantryItems.
class DeliveryRepository {
  DeliveryRepository({DeviceIdentity? deviceIdentity})
    : _device = deviceIdentity ?? DeviceIdentity.instance;

  final _db = FirebaseFirestore.instance;
  final DeviceIdentity _device;

  CollectionReference<Map<String, dynamic>> get _deliveries =>
      _db.collection('deliveries');

  Delivery _parseOrThrow(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Delivery.fromFirestore(doc);
    } catch (e) {
      throw StateError(
        "Fallo el parseo del doc de Delivery ${doc.id} en la colección deliveries: $e",
      );
    }
  }

  /// Quién (instalación) y cuándo (reloj del dispositivo) hizo la escritura.
  Future<Map<String, Object>> _trace() async => {
    'deviceId': await _device.id,
    'localTimestamp': Timestamp.fromDate(DateTime.now()),
  };

  /// Registra la entrega y regresa su id. Si se registra como entregada, la
  /// Cloud Function agrega sus productos a la despensa de la familia (con
  /// este mismo deliveryId).
  Future<String> registerDelivery(Delivery delivery) async {
    final error = delivery.validate();
    if (error != null) throw ArgumentError(error);
    if (delivery.status != DeliveryStatus.scheduled &&
        delivery.status != DeliveryStatus.delivered) {
      throw ArgumentError(
        'Una entrega nueva solo puede registrarse programada o entregada',
      );
    }

    final trace = await _trace();
    final ref = _deliveries.doc();
    await ref.set({...delivery.toFirestore(), ...trace});
    return ref.id;
  }

  /// Marca como entregada una entrega programada; después la Cloud Function
  /// agrega sus productos a la despensa de la familia, menos los que ya
  /// caducaron. Regresa cuántos caducados hay hoy en este dispositivo (la
  /// función decide con la hora registrada por el dispositivo, si es creíble;
  /// de lo contrario usa la hora en que la escritura llega al servidor). Las
  /// reglas lo rechazan si la entrega ya no estaba programada (p. ej. otro
  /// dispositivo ya la entregó).
  Future<int> markDelivered(Delivery delivery) async {
    if (delivery.status != DeliveryStatus.scheduled) {
      throw StateError('La entrega ya no está programada');
    }

    final now = DateTime.now();
    final trace = await _trace();
    await _deliveries.doc(delivery.deliveryId).update({
      'status': DeliveryStatus.delivered.name,
      ...trace,
    });
    return delivery.items.where((item) => item.isExpiredOn(now)).length;
  }

  /// Reasigna una entrega programada a [receiver] y regresa el id de la
  /// entrega nueva. En un solo batch: la nueva queda programada para
  /// [receiver] con la misma fecha, despensas, cuota y productos (sin las
  /// notas) y la original queda como reasignada, apuntando a la nueva. Las
  /// reglas (validReassignment) exigen que ambas escrituras vayan juntas.
  Future<String> reassignDelivery(Delivery delivery, Family receiver) async {
    if (delivery.status != DeliveryStatus.scheduled) {
      throw StateError('La entrega ya no está programada');
    }
    if (receiver.familyId == delivery.familyId) {
      throw ArgumentError('Elige una familia distinta a la de la entrega');
    }

    final newRef = _deliveries.doc();
    final reassigned = Delivery(
      deliveryId: newRef.id,
      familyId: receiver.familyId,
      familyName: receiver.displayName,
      deliveryDate: delivery.deliveryDate,
      packages: delivery.packages,
      recoveryFee: delivery.recoveryFee,
      justification: delivery.justification,
      status: DeliveryStatus.scheduled,
      items: delivery.items,
      createdAt: DateTime.now(),
      reassignedFrom: delivery.deliveryId,
    );

    final batch = _db.batch();
    final trace = await _trace();
    batch.set(newRef, {...reassigned.toFirestore(), ...trace});
    batch.update(_deliveries.doc(delivery.deliveryId), {
      'status': DeliveryStatus.reassigned.name,
      'reassignedTo': newRef.id,
      ...trace,
    });
    await batch.commit();
    return newRef.id;
  }

  /// Cancela una entrega programada; sus productos no entran a la despensa.
  Future<void> cancelDelivery(Delivery delivery) async {
    if (delivery.status != DeliveryStatus.scheduled) {
      throw StateError('Solo se pueden cancelar entregas programadas');
    }

    final trace = await _trace();
    await _deliveries.doc(delivery.deliveryId).update({
      'status': DeliveryStatus.cancelled.name,
      ...trace,
    });
  }

  /// Las [limit] entregas más recientes más todas las programadas (aunque
  /// sean más antiguas), ordenadas de la más reciente a la más antigua.
  /// pendingSync indica que el cambio sigue en el dispositivo y aún no llega
  /// al servidor.
  Stream<List<DeliveryWithSync>> watchRecentDeliveries({int limit = 50}) {
    final recent = _deliveries
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true);
    final scheduled = _deliveries
        .where('status', isEqualTo: DeliveryStatus.scheduled.name)
        .snapshots(includeMetadataChanges: true);

    return _combine(recent, scheduled).map((snapshots) {
      final byId = <String, DeliveryWithSync>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          byId[doc.id] = (
            delivery: _parseOrThrow(doc),
            pendingSync: doc.metadata.hasPendingWrites,
          );
        }
      }
      return byId.values.toList()
        ..sort((a, b) => b.delivery.createdAt.compareTo(a.delivery.createdAt));
    });
  }

  /// Emite los últimos valores de ambos streams cuando los dos ya emitieron.
  static Stream<List<QuerySnapshot<Map<String, dynamic>>>> _combine(
    Stream<QuerySnapshot<Map<String, dynamic>>> first,
    Stream<QuerySnapshot<Map<String, dynamic>>> second,
  ) {
    late StreamController<List<QuerySnapshot<Map<String, dynamic>>>> controller;
    QuerySnapshot<Map<String, dynamic>>? a;
    QuerySnapshot<Map<String, dynamic>>? b;
    final subscriptions = <StreamSubscription<Object?>>[];

    void emit() {
      if (a != null && b != null) controller.add([a!, b!]);
    }

    controller = StreamController(
      onListen: () {
        subscriptions
          ..add(
            first.listen((value) {
              a = value;
              emit();
            }, onError: controller.addError),
          )
          ..add(
            second.listen((value) {
              b = value;
              emit();
            }, onError: controller.addError),
          );
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }
}
