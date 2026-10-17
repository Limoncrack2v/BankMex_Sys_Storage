import 'package:bank_storage_app/domain/models/recipe_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('without limits every recipe fits', () {
    const request = RecipeRequest();

    expect(request.fitsTime(500), isTrue);
    expect(request.minutesOver(500), 0);
    expect(request.cravingText, isNull);
    expect(request.excludeRecipeIds, isEmpty);
  });

  test('compares the minutes with the limit', () {
    const request = RecipeRequest(maxPrepMinutes: 30);

    expect(request.fitsTime(30), isTrue);
    expect(request.fitsTime(31), isFalse);
    expect(request.minutesOver(40), 10);
    expect(request.minutesOver(10), 0);
  });

  test('a recipe without a time never fits a limit', () {
    const request = RecipeRequest(maxPrepMinutes: 30);

    expect(request.fitsTime(0), isFalse);
    expect(request.fitsTime(-5), isFalse);
    expect(request.minutesOver(0), 0);
    expect(const RecipeRequest().fitsTime(0), isTrue);
  });

  test('a blank craving is no craving', () {
    expect(const RecipeRequest(craving: '   ').cravingText, isNull);
    expect(const RecipeRequest(craving: ' Atún ').cravingText, 'Atún');
  });

  test('excluding keeps the search and restarted forgets what was seen', () {
    const request = RecipeRequest(
      craving: 'Frijol',
      cravingIsProduct: true,
      maxPrepMinutes: 30,
    );
    final seen = request.excluding('a').excluding('b');

    expect(seen.excludeRecipeIds, {'a', 'b'});
    expect(seen.cravingText, 'Frijol');
    expect(seen.cravingIsProduct, isTrue);
    expect(seen.maxPrepMinutes, 30);
    expect(request.excludeRecipeIds, isEmpty);
    expect(seen.restarted(), request);
  });

  test('keeps its own copy of the seen recipes', () {
    final ids = {'a'};
    final request = RecipeRequest.excludingAll(ids);
    final hash = request.hashCode;
    ids.add('b');

    expect(request.excludeRecipeIds, {'a'});
    expect(request.hashCode, hash);
    expect(
      () => const RecipeRequest().excluding('x').excludeRecipeIds.add('y'),
      throwsUnsupportedError,
    );
  });

  test('toJson has only the request, with sorted ids', () {
    final json = const RecipeRequest(craving: ' sopa ')
        .excluding('z')
        .excluding('a')
        .toJson();

    expect(json, {
      'craving': 'sopa',
      'cravingIsProduct': false,
      'maxPrepMinutes': null,
      'excludeRecipeIds': ['a', 'z'],
    });
  });

  test('== and hashCode ignore the order of the seen recipes', () {
    final ab = const RecipeRequest().excluding('a').excluding('b');
    final ba = const RecipeRequest().excluding('b').excluding('a');

    expect(ab, ba);
    expect(ab.hashCode, ba.hashCode);
    expect(ab, isNot(const RecipeRequest().excluding('a')));
    expect(
      const RecipeRequest(craving: ' sopa '),
      const RecipeRequest(craving: 'sopa'),
    );
    expect(
      const RecipeRequest(maxPrepMinutes: 30),
      isNot(const RecipeRequest()),
    );
    // Una opción de la despensa no es lo mismo que el texto escrito.
    expect(
      const RecipeRequest(craving: 'Frijol', cravingIsProduct: true),
      isNot(const RecipeRequest(craving: 'Frijol')),
    );
  });
}
