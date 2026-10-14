enum AuthMethod { email, phone }

class User {
  const User({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.passwordHash,
    required this.passwordSalt,
    required this.authMethod,
    this.emailVerified = false,
    this.phoneVerified = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String passwordHash;
  final String passwordSalt;
  final AuthMethod authMethod;
  final bool emailVerified;
  final bool phoneVerified;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isVerified =>
      authMethod == AuthMethod.email ? emailVerified : phoneVerified;

  User copyWith({
    String? name,
    String? email,
    String? phone,
    String? passwordHash,
    String? passwordSalt,
    AuthMethod? authMethod,
    bool? emailVerified,
    bool? phoneVerified,
    DateTime? updatedAt,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      authMethod: authMethod ?? this.authMethod,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'password_hash': passwordHash,
      'password_salt': passwordSalt,
      'auth_method': authMethod.name,
      'email_verified': emailVerified ? 1 : 0,
      'phone_verified': phoneVerified ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as String,
      name: map['name'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      passwordHash: map['password_hash'] as String,
      passwordSalt: map['password_salt'] as String,
      authMethod: (map['auth_method'] as String?) == 'phone'
          ? AuthMethod.phone
          : AuthMethod.email,
      emailVerified: (map['email_verified'] as int? ?? 0) == 1,
      phoneVerified: (map['phone_verified'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  /// Safe representation for client-side state without password secrets
  Map<String, dynamic> toSafeJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'auth_method': authMethod.name,
      'email_verified': emailVerified,
      'phone_verified': phoneVerified,
      'is_verified': isVerified,
    };
  }

  @override
  String toString() =>
      'User(id: $id, name: $name, method: ${authMethod.name}, verified: $isVerified)';
}
