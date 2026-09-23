class ChildProfile {
  const ChildProfile({required this.age, required this.weight});

  final int age;
  final double weight;

  factory ChildProfile.fromMap(Map<String, dynamic> map) {
    return ChildProfile(
      age: (map['age'] as num).toInt(),
      weight: (map['weight'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {'age': age, 'weight': weight};

  Map<String, dynamic> toJson() => toMap();
}
