import '../firestore_codec.dart';
import 'appliance.dart';

/// draft: Staff la prepara y las familias no la ven. pending: espera la
/// revisión del nutriólogo. approved: la aprobó el nutriólogo y las familias
/// la ven. Solo el nutriólogo la aprueba (firestore.rules).
enum RecipeStatus {
  draft,
  pending,
  approved;

  String get firestoreValue => name;

  /// Un valor que no se reconoce se lee como pending: espera revisión y las
  /// familias no la ven.
  static RecipeStatus fromFirestore(String? value) {
    return switch (value) {
      'draft' => RecipeStatus.draft,
      'approved' => RecipeStatus.approved,
      _ => RecipeStatus.pending,
    };
  }
}

/// Etiquetas nutricionales de una receta. [id] es el valor que se guarda en
/// recipes/{id}.nutritionalTags.
enum NutritionalTag {
  lowSodium('bajoEnSodio'),
  lowSugar('bajoEnAzucar'),
  lowFat('bajoEnGrasa'),
  highFiber('altoEnFibra'),
  highProtein('altoEnProteina'),
  vegetarian('vegetariano'),
  diabeticFriendly('aptoDiabeticos');

  const NutritionalTag(this.id);

  final String id;

  /// null si [id] no es una etiqueta conocida.
  static NutritionalTag? fromId(String id) {
    for (final tag in values) {
      if (tag.id == id) return tag;
    }
    return null;
  }
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.productName,
    required this.quantity,
    required this.unit,
  });

  final String productName;
  final double quantity;
  final String unit;

  factory RecipeIngredient.fromMap(Map<String, dynamic> map) {
    return RecipeIngredient(
      productName: map['productName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: map['unit'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'productName': productName,
        'quantity': quantity,
        'unit': unit,
      };

  Map<String, dynamic> toJson() => toMap();

  RecipeIngredient copyWith({
    String? productName,
    double? quantity,
    String? unit,
  }) {
    return RecipeIngredient(
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
    );
  }
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.ingredients,
    required this.steps,
    required this.prepTimeMinutes,
    required this.caloriesPerServing,
    required this.status,
    this.dietaryTags = const [],
    this.nutritionalTags = const [],
    this.requiredEquipment = const [],
    this.image = '',
    this.servings = 4,
    this.approvedBy,
    this.approvedAt,
    this.reviewNote,
    this.rejectedBy,
    this.rejectedAt,
  });

  final String id;
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final int prepTimeMinutes;
  final int caloriesPerServing;
  final RecipeStatus status;
  final List<String> dietaryTags;

  /// Ids de [NutritionalTag], sin repetir.
  final List<String> nutritionalTags;

  /// Ids de [Appliance] que hacen falta para prepararla, sin repetir. Vacía
  /// si no necesita ninguno. Son los mismos ids de families/{id}.appliances
  /// para poder compararlos con lo que tiene cada hogar.
  final List<String> requiredEquipment;
  final String image;
  final int servings;

  /// Quién la aprobó y cuándo (uid del nutriólogo). Solo en una approved.
  final String? approvedBy;
  final DateTime? approvedAt;

  /// Por qué la rechazó el nutriólogo, quién y cuándo. Solo en un draft que
  /// regresó de revisión; Staff los borra al volver a enviarla.
  final String? reviewNote;
  final String? rejectedBy;
  final DateTime? rejectedAt;

  /// Máximo del motivo de un rechazo (firestore.rules: validReview).
  static const int maxReviewNoteLength = 300;

  factory Recipe.fromMap(String id, Map<String, dynamic> map) {
    final rawIngredients = map['ingredients'] as List<dynamic>? ?? const [];
    final rawSteps = map['steps'] as List<dynamic>? ?? const [];
    final rawTags = map['dietaryTags'] as List<dynamic>? ?? const [];
    final rawNutritional =
        map['nutritionalTags'] as List<dynamic>? ?? const [];
    final rawEquipment = map['requiredEquipment'] as List<dynamic>? ?? const [];
    return Recipe(
      id: id,
      name: map['name'] as String? ?? '',
      ingredients: rawIngredients
          .map((item) => RecipeIngredient.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
      steps: rawSteps.map((item) => item.toString()).toList(),
      prepTimeMinutes: (map['prepTimeMinutes'] as num?)?.toInt() ?? 0,
      caloriesPerServing: (map['caloriesPerServing'] as num?)?.toInt() ?? 0,
      status: RecipeStatus.fromFirestore(map['status'] as String?),
      dietaryTags: rawTags.map((item) => item.toString()).toList(),
      nutritionalTags: rawNutritional.map((item) => item.toString()).toList(),
      requiredEquipment: rawEquipment.map((item) => item.toString()).toList(),
      image: map['image'] as String? ?? '',
      servings: (map['servings'] as num?)?.toInt() ?? 4,
      approvedBy: map['approvedBy'] as String?,
      approvedAt: decodeDate(map['approvedAt']),
      reviewNote: map['reviewNote'] as String?,
      rejectedBy: map['rejectedBy'] as String?,
      rejectedAt: decodeDate(map['rejectedAt']),
    );
  }

  /// Los campos de revisión solo van si tienen valor: Staff nunca los escribe
  /// (las reglas lo niegan), así que su ausencia es lo normal.
  Map<String, dynamic> toMap() => {
        'name': name,
        'ingredients': ingredients.map((item) => item.toMap()).toList(),
        'steps': steps,
        'prepTimeMinutes': prepTimeMinutes,
        'caloriesPerServing': caloriesPerServing,
        'status': status.firestoreValue,
        'dietaryTags': dietaryTags,
        'nutritionalTags': nutritionalTags,
        'requiredEquipment': requiredEquipment,
        'image': image,
        'servings': servings,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (approvedAt != null) 'approvedAt': approvedAt,
        if (reviewNote != null) 'reviewNote': reviewNote,
        if (rejectedBy != null) 'rejectedBy': rejectedBy,
        if (rejectedAt != null) 'rejectedAt': rejectedAt,
      };

  Map<String, dynamic> toJson() => {'id': id, ...toMap()};

  Recipe copyWith({
    String? id,
    String? name,
    List<RecipeIngredient>? ingredients,
    List<String>? steps,
    int? prepTimeMinutes,
    int? caloriesPerServing,
    RecipeStatus? status,
    List<String>? dietaryTags,
    List<String>? nutritionalTags,
    List<String>? requiredEquipment,
    String? image,
    int? servings,
  }) {
    return Recipe(
      id: id ?? this.id,
      name: name ?? this.name,
      ingredients: ingredients ?? this.ingredients,
      steps: steps ?? this.steps,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      caloriesPerServing: caloriesPerServing ?? this.caloriesPerServing,
      status: status ?? this.status,
      dietaryTags: dietaryTags ?? this.dietaryTags,
      nutritionalTags: nutritionalTags ?? this.nutritionalTags,
      requiredEquipment: requiredEquipment ?? this.requiredEquipment,
      image: image ?? this.image,
      servings: servings ?? this.servings,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
      reviewNote: reviewNote,
      rejectedBy: rejectedBy,
      rejectedAt: rejectedAt,
    );
  }

  /// La receta con otro [status], como la deja Staff: sale de approved o
  /// vuelve a revisión, así que se borra lo que dejó el nutriólogo (quién la
  /// aprobó, y el motivo del rechazo si ya se reenvía). Un draft conserva el
  /// motivo de su rechazo.
  Recipe withStaffStatus(RecipeStatus status) {
    assert(status != RecipeStatus.approved, 'Staff no aprueba recetas');
    final keepsRejection = status == RecipeStatus.draft;
    return Recipe(
      id: id,
      name: name,
      ingredients: ingredients,
      steps: steps,
      prepTimeMinutes: prepTimeMinutes,
      caloriesPerServing: caloriesPerServing,
      status: status,
      dietaryTags: dietaryTags,
      nutritionalTags: nutritionalTags,
      requiredEquipment: requiredEquipment,
      image: image,
      servings: servings,
      reviewNote: keepsRejection ? reviewNote : null,
      rejectedBy: keepsRejection ? rejectedBy : null,
      rejectedAt: keepsRejection ? rejectedAt : null,
    );
  }

  /// Ids de [nutritionalTags] que esta versión de la app no conoce, sin
  /// repetir (un id repetido haría que la validación rechace la receta). El
  /// formulario los conserva al editar.
  List<String> get unknownNutritionalTags => {
    for (final id in nutritionalTags)
      if (NutritionalTag.fromId(id) == null) id,
  }.toList();

  /// Igual que [unknownNutritionalTags], para [requiredEquipment].
  List<String> get unknownEquipment => {
    for (final id in requiredEquipment)
      if (Appliance.fromId(id) == null) id,
  }.toList();

  /// [keep] son ids que ya estaban guardados en la receta: se aceptan aunque
  /// esta versión de la app no los conozca, para no borrarlos al editar.
  static String? validateNutritionalTags(
    List<String> tags, {
    Set<String> keep = const {},
  }) {
    final unknown = tags.where(
      (id) => NutritionalTag.fromId(id) == null && !keep.contains(id),
    );
    if (unknown.isNotEmpty) {
      return 'Etiqueta nutricional desconocida';
    }
    if (tags.toSet().length != tags.length) {
      return 'Las etiquetas nutricionales no pueden repetirse';
    }
    return null;
  }

  /// Mismas reglas que los electrodomésticos del hogar
  /// ([Appliance.validateIds]); [keep] igual que en [validateNutritionalTags].
  static String? validateRequiredEquipment(
    List<String> equipment, {
    Set<String> keep = const {},
  }) => Appliance.validateIds(equipment, keep: keep);
}
