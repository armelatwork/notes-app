enum AuthType { google, local }

class AppUser {
  final String id;
  final String displayName;
  final String? email;
  final AuthType type;

  const AppUser({
    required this.id,
    required this.displayName,
    this.email,
    required this.type,
  });
}
