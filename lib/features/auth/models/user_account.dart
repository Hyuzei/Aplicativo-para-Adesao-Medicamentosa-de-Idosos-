enum AccountRole {
  caregiver,
  caredFor,
}

class UserAccount {
  const UserAccount({
    this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.passwordSalt,
    required this.passwordHash,
  });

  final String? id;
  final String name;
  final String email;
  final AccountRole role;
  final String passwordSalt;
  final String passwordHash;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'passwordSalt': passwordSalt,
    'passwordHash': passwordHash,
  };

  factory UserAccount.fromJson(Map<String, Object?> json) => UserAccount(
    id: json['id'] as String?,
    name: json['name']! as String,
    email: json['email']! as String,
    role: AccountRole.values.byName(json['role']! as String),
    passwordSalt: json['passwordSalt']! as String,
    passwordHash: json['passwordHash']! as String,
  );
}
