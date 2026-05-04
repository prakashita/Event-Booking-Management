class AppConstants {
  // API
  static const String apiBase = '/api/v1';
  static const String wsPath = '/api/v1/chat/ws';

  // Google OAuth (provided via --dart-define)
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  // Roles
  static const List<String> allRoles = [
    'admin',
    'registrar',
    'vice_chancellor',
    'deputy_registrar',
    'finance_team',
    'faculty',
    'facility_manager',
    'marketing',
    'it',
    'iqac',
    'transport',
  ];

  static const List<String> iqacAllowedRoles = ['iqac'];
  static const List<String> adminRoles = [
    'admin',
    'registrar',
    'vice_chancellor',
    'deputy_registrar',
    'finance_team',
  ];
  static const List<String> approvalRoles = [
    'registrar',
    'vice_chancellor',
    'deputy_registrar',
    'finance_team',
  ];
  static const List<String> facilityRoles = ['facility_manager'];
  static const List<String> marketingRoles = ['marketing'];
  static const List<String> itRoles = ['it'];
  static const List<String> transportRoles = ['transport'];

  // Event status
  static const String statusUpcoming = 'upcoming';
  static const String statusOngoing = 'ongoing';
  static const String statusCompleted = 'completed';
  static const String statusClosed = 'closed';

  // Approval status
  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusRejected = 'rejected';

  // Marketing item types
  static const List<String> marketingItems = [
    'Poster',
    'Banner',
    'LinkedIn Post',
    'Instagram Post',
    'Photography',
    'Video',
    'Brochure',
    'Invitation Card',
  ];

  // Publication types
  static const List<String> publicationTypes = [
    'journal_article',
    'book',
    'webpage',
    'video',
    'newspaper',
    'report',
  ];

  // IQAC criteria
  static const List<Map<String, String>> iqacCriteria = [
    {'key': '1', 'label': 'Curricular Aspects'},
    {'key': '2', 'label': 'Teaching-Learning and Evaluation'},
    {'key': '3', 'label': 'Research, Innovations and Extension'},
    {'key': '4', 'label': 'Infrastructure and Learning Resources'},
    {'key': '5', 'label': 'Student Support and Progression'},
    {'key': '6', 'label': 'Governance, Leadership and Management'},
    {'key': '7', 'label': 'Institutional Values and Best Practices'},
  ];

  // Secure storage keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'auth_user';

  // Pagination
  static const int pageSize = 20;

  // File size limits
  static const int maxReportSizeMb = 10;
  static const int maxIqacFileSizeMb = 20;
}
