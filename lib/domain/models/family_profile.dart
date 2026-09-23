import 'child_profile.dart';

class FamilyProfile {
  const FamilyProfile({
    required this.id,
    required this.authUid,
    required this.adults,
    required this.children,
    required this.dietaryRestrictions,
  });

  final String id;
  final String authUid;
  final int adults;
  final List<ChildProfile> children;
  final List<String> dietaryRestrictions;

  factory FamilyProfile.fromMap(String id, Map<String, dynamic> map) {
    final rawChildren = map['children'] as List<dynamic>? ?? const [];
    final rawRestrictions =
        map['dietaryRestrictions'] as List<dynamic>? ?? const [];
    return FamilyProfile(
      id: id,
      authUid: map['authUid'] as String? ?? '',
      adults: (map['adults'] as num?)?.toInt() ?? 0,
      children: rawChildren
          .map((item) => ChildProfile.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
      dietaryRestrictions: rawRestrictions.map((item) => item.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'authUid': authUid,
        'adults': adults,
        'children': children.map((child) => child.toMap()).toList(),
        'dietaryRestrictions': dietaryRestrictions,
      };

  Map<String, dynamic> toJson() => {'id': id, ...toMap()};
}
