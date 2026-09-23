enum RecipeStatus {
  pending,
  approved;

  String get firestoreValue {
    switch (this) {
      case RecipeStatus.pending:
        return 'pending';
      case RecipeStatus.approved:
        return 'approved';
    }
  }

  static RecipeStatus fromFirestore(String? value) {
    switch (value) {
      case 'approved':
        return RecipeStatus.approved;
      default:
        return RecipeStatus.pending;
    }
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
    this.image = '',
    this.servings = 4,
  });

  final String id;
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final int prepTimeMinutes;
  final int caloriesPerServing;
  final RecipeStatus status;
  final List<String> dietaryTags;
  final String image;
  final int servings;

  factory Recipe.fromMap(String id, Map<String, dynamic> map) {
    final rawIngredients = map['ingredients'] as List<dynamic>? ?? const [];
    final rawSteps = map['steps'] as List<dynamic>? ?? const [];
    final rawTags = map['dietaryTags'] as List<dynamic>? ?? const [];
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
      image: map['image'] as String? ?? '',
      servings: (map['servings'] as num?)?.toInt() ?? 4,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ingredients': ingredients.map((item) => item.toMap()).toList(),
        'steps': steps,
        'prepTimeMinutes': prepTimeMinutes,
        'caloriesPerServing': caloriesPerServing,
        'status': status.firestoreValue,
        'dietaryTags': dietaryTags,
        'image': image,
        'servings': servings,
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
      image: image ?? this.image,
      servings: servings ?? this.servings,
    );
  }
}
