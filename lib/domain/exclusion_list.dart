import '../data/models/member.dart';

// Palabras de los ingredientes que una familia debe evitar, por alergia o por
// enfermedad crónica. Las usan las advertencias de las recetas
// (lib/ui/models/recipe.dart) y [NutritionTargets].

/// Palabras que delatan cada alérgeno en el nombre de un ingrediente, sin
/// acentos y en singular (la forma de normalizeName en
/// lib/ui/models/recipe.dart).
const allergenKeywords = <Allergy, List<String>>{
  Allergy.dairy: [
    'leche',
    'yogurt',
    'yogur',
    'queso',
    'crema',
    'mantequilla',
    'requeson',
    'jocoque',
    'nata',
    'helado',
  ],
  Allergy.gluten: [
    'pan',
    'pasta',
    'harina',
    'trigo',
    'avena',
    'galleta',
    'cereal',
    'fideo',
    'espagueti',
    'spaghetti',
    'macarron',
    'codito',
    'lasana',
    'bolillo',
    'telera',
    'empanada',
    'panque',
    'cebada',
    'centeno',
    'cuscus',
  ],
  Allergy.peanut: ['cacahuate', 'mani'],
  Allergy.shellfish: [
    'camaron',
    'marisco',
    'pulpo',
    'calamar',
    'ostion',
    'jaiba',
    'langosta',
    'langostino',
    'almeja',
    'mejillon',
  ],
  Allergy.egg: ['huevo', 'mayonesa', 'merengue'],
  Allergy.soy: ['soya', 'soja', 'tofu'],
};

/// Lo que conviene evitar con cada enfermedad, en la misma forma:
/// azúcares con diabetes, sal y embutidos con hipertensión y
/// enfermedad renal (también refrescos, por el fósforo), y grasas saturadas
/// con colesterol alto. Igual que con las alergias, se busca en el nombre del
/// ingrediente palabra por palabra.
const conditionKeywords = <ChronicCondition, List<String>>{
  ChronicCondition.diabetes: [
    'azucar',
    'refresco',
    'jugo',
    'miel',
    'dulce',
    'mermelada',
    'chocolate',
    'piloncillo',
    'cajeta',
    'jarabe',
  ],
  ChronicCondition.hypertension: [
    'sal',
    'consome',
    'jamon',
    'salchicha',
    'chorizo',
    'tocino',
    'embutido',
  ],
  ChronicCondition.obesity: [
    'azucar',
    'refresco',
    'dulce',
    'manteca',
    'chicharron',
    'fritura',
  ],
  ChronicCondition.kidneyDisease: [
    'sal',
    'consome',
    'refresco',
    'jamon',
    'salchicha',
    'chorizo',
    'embutido',
  ],
  ChronicCondition.highCholesterol: [
    'manteca',
    'mantequilla',
    'tocino',
    'chicharron',
    'chorizo',
    'crema',
  ],
};

/// Lista de exclusión del hogar: las palabras de los alérgenos y de las
/// enfermedades crónicas de [members], sin repetir y en orden alfabético.
List<String> exclusionKeywords(List<Member> members) {
  final keywords = <String>{
    for (final member in members) ...[
      for (final allergy in member.allergies ?? const <Allergy>[])
        ...?allergenKeywords[allergy],
      for (final condition
          in member.chronicConditions ?? const <ChronicCondition>[])
        ...?conditionKeywords[condition],
    ],
  };
  return keywords.toList()..sort();
}
