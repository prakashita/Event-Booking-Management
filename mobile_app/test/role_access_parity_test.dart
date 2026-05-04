import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/constants/app_constants.dart';

void main() {
  group('AppConstants role access parity with website dashboard', () {
    test('admin-only sections stay admin-only', () {
      expect(AppConstants.canAccessCalendarUpdates('admin'), isTrue);
      expect(AppConstants.canAccessUserApprovals('admin'), isTrue);
      expect(AppConstants.canAccessAdminConsole('admin'), isTrue);

      for (final role in const [
        'registrar',
        'vice_chancellor',
        'deputy_registrar',
        'finance_team',
        'faculty',
        'facility_manager',
        'marketing',
        'it',
        'transport',
        'iqac',
      ]) {
        expect(
          AppConstants.canAccessCalendarUpdates(role),
          isFalse,
          reason: '$role should match the website calendar updates gate',
        );
        expect(AppConstants.canAccessUserApprovals(role), isFalse);
        expect(AppConstants.canAccessAdminConsole(role), isFalse);
      }
    });

    test('approval, requirements, reports, and IQAC gates match roles', () {
      for (final role in AppConstants.approvalRoles) {
        expect(AppConstants.canAccessApprovals(role), isTrue);
        expect(AppConstants.canAccessEventReports(role), isTrue);
      }

      for (final role in const [
        'facility_manager',
        'marketing',
        'it',
        'transport',
      ]) {
        expect(AppConstants.canAccessRequirements(role), isTrue);
      }

      expect(AppConstants.canAccessEventReports('admin'), isTrue);
      expect(AppConstants.canAccessIqac('iqac'), isTrue);
      expect(AppConstants.canAccessIqac('admin'), isFalse);
      expect(AppConstants.canAccessApprovals('faculty'), isFalse);
      expect(AppConstants.canAccessRequirements('faculty'), isFalse);
      expect(AppConstants.canAccessEventReports('faculty'), isFalse);
    });
  });
}
