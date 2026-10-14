import '../firestore_codec.dart';
import '../recipe_adjustment.dart';
import 'recipe.dart';

enum AdjustmentStatus {
  /// La familia ya tiene la sugerencia y espera al nutriólogo: sigue viendo la
  /// receta original.
  pending,

  /// El nutriólogo la aprobó: la familia ve la receta adaptada.
  approved,

  /// El nutriólogo la rechazó, con un motivo: nada cambia.
  rejected;

  static AdjustmentStatus fromFirestore(String? value) => switch (value) {
    'approved' => AdjustmentStatus.approved,
    'rejected' => AdjustmentStatus.rejected,
    _ => AdjustmentStatus.pending,
  };
}

/// Una adaptación de una receta para un hogar (adjustments/{id}): lo que sugirió
/// [RecipeAdjustmentRules] y lo que decidió el nutriólogo. Nunca lleva nombres
/// de la familia ni de sus integrantes, solo el tamaño del hogar y el motivo de
/// cada cambio. Nadie edita su contenido después de crearla (firestore.rules).
class RecipeAdjustment {
  const RecipeAdjustment({
    required this.id,
    required this.familyId,
    required this.recipeId,
    required this.baseSignature,
    required this.householdSize,
    required this.servings,
    required this.ingredients,
    required this.changes,
    required this.summary,
    required this.status,
    this.rejectionReason,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
  });

  final String id;
  final String familyId;
  final String recipeId;

  /// [recipeSignature] de la receta cuando se sugirió. Si ya no coincide con
  /// la actual, la receta se editó y esta adaptación no se aplica.
  final String baseSignature;
  final int householdSize;
  final int servings;
  final List<RecipeIngredient> ingredients;
  final List<AdjustmentChange> changes;
  final String summary;
  final AdjustmentStatus status;
  final String? rejectionReason;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  /// Máximos que revisa firestore.rules (validAdjustment).
  static const int maxChanges = AdjustmentChange.maxPerSuggestion;
  static const int maxSummaryLength = 300;
  static const int maxReasonLength = 300;

  /// La sugerencia de [RecipeAdjustmentRules] como adaptación nueva, pendiente.
  factory RecipeAdjustment.pending({
    required String familyId,
    required RecipeAdjustmentSuggestion suggestion,
  }) => RecipeAdjustment(
    id: '',
    familyId: familyId,
    recipeId: suggestion.recipeId,
    baseSignature: suggestion.baseSignature,
    householdSize: suggestion.householdSize,
    servings: suggestion.servings,
    ingredients: suggestion.ingredients,
    changes: suggestion.changes,
    summary: suggestion.summary,
    status: AdjustmentStatus.pending,
  );

  factory RecipeAdjustment.fromMap(String id, Map<String, dynamic> map) {
    final rawIngredients = map['ingredients'] as List<dynamic>? ?? const [];
    final rawChanges = map['changes'] as List<dynamic>? ?? const [];
    return RecipeAdjustment(
      id: id,
      familyId: decodeRefId(map['familyId']) ?? '',
      recipeId: map['recipeId'] as String? ?? '',
      baseSignature: map['baseSignature'] as String? ?? '',
      householdSize: (map['householdSize'] as num?)?.toInt() ?? 0,
      servings: (map['servings'] as num?)?.toInt() ?? 0,
      ingredients: [
        for (final item in rawIngredients)
          RecipeIngredient.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
      changes: [
        for (final item in rawChanges)
          AdjustmentChange.fromMap(Map<String, dynamic>.from(item as Map)),
      ],
      summary: map['summary'] as String? ?? '',
      status: AdjustmentStatus.fromFirestore(map['status'] as String?),
      rejectionReason: map['rejectionReason'] as String?,
      reviewedBy: map['reviewedBy'] as String?,
      reviewedAt: decodeDate(map['reviewedAt']),
      createdAt: decodeDate(map['createdAt']),
    );
  }

  /// Lo que se escribe al crearla (la familia): sin revisión. familyId y
  /// createdAt los pone el repositorio (una referencia y la hora del servidor).
  Map<String, dynamic> toMap() => {
    'recipeId': recipeId,
    'baseSignature': baseSignature,
    'householdSize': householdSize,
    'servings': servings,
    'ingredients': [for (final item in ingredients) item.toMap()],
    'changes': [for (final item in changes) item.toMap()],
    'summary': summary,
    'status': status.name,
  };
}
