const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);
const String kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const String kGoogleServerClientId =
String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class AppSession {
  const AppSession({
    required this.baseUrl,
    required this.token,
    required this.role,
    required this.name,
    required this.email,
  });

  final String baseUrl;
  final String token;
  final String role;
  final String name;
  final String email;

  bool get isAdmin => role == 'admin';
  bool get isFaculty => role == 'faculty';
  bool get isRegistrar => role == 'registrar';

  String get displayRole {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'faculty':
        return 'Faculty';
      case 'registrar':
        return 'Registrar';
      default:
        return role.replaceAll('_', ' ').toUpperCase();
    }
  }
}
