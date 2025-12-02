class Patient {
  final String id;
  final String name;
  final String? phoneNumber;
  final String? email;
  final int? age;
  final String? gender;
  final DateTime createdAt;

  Patient({
    required this.id,
    required this.name,
    this.phoneNumber,
    this.email,
    this.age,
    this.gender,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] ?? json['patientId'] ?? '',
      name: json['name'] ?? '',
      phoneNumber: json['phoneNumber'],
      email: json['email'],
      age: json['age'],
      gender: json['gender'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'email': email,
      'age': age,
      'gender': gender,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
