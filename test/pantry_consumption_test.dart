import 'package:flutter_test/flutter_test.dart';

import 'package:bank_storage_app/data/repositories/pantry_repository.dart';

// Solo se usa el método estático: el constructor de PantryRepository
// necesita Firebase.
void main() {
  group('PantryRepository.remainingAfter', () {
    test('subtracts the consumed amount', () {
      expect(PantryRepository.remainingAfter(2, 0.5), 1.5);
      expect(PantryRepository.remainingAfter(8, 3), 5);
      expect(PantryRepository.remainingAfter(3.5, 1.25), 2.25);
    });

    test('consuming everything leaves exactly 0', () {
      expect(PantryRepository.remainingAfter(2, 2), 0);
      expect(PantryRepository.remainingAfter(0.3, 0.3), 0);
    });

    test('repeated small consumptions leave no floating point residue', () {
      var quantity = 0.3;
      final steps = <double>[];
      for (var i = 0; i < 3; i++) {
        quantity = PantryRepository.remainingAfter(quantity, 0.1);
        steps.add(quantity);
      }

      expect(steps, [0.2, 0.1, 0]);
      expect(quantity, 0);
      expect(quantity <= 0, isTrue);
    });

    test('ten consumptions of 0.1 empty one unit exactly', () {
      var quantity = 1.0;
      for (var i = 0; i < 10; i++) {
        quantity = PantryRepository.remainingAfter(quantity, 0.1);
      }
      expect(quantity, 0);
    });

    test('rounds to 3 decimals', () {
      expect(PantryRepository.remainingAfter(1, 0.3333), 0.667);
    });

    test('over-consumption clamps to 0', () {
      expect(PantryRepository.remainingAfter(1, 1.5), 0);
      expect(PantryRepository.remainingAfter(0.1, 5), 0);
    });
  });
}
