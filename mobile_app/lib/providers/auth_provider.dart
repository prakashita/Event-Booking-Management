import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../utils/friendly_error.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _authService = AuthService();
  final _api = ApiService();

  User? _user;
  String? _token;
  AuthStatus _status = AuthStatus.loading;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  AuthStatus get status => _status;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  String get approvalStatus {
    return (_user?.approvalStatus ?? 'approved').trim().toLowerCase();
  }

  bool get isApprovalPending => approvalStatus == 'pending';
  bool get isApprovalRejected => approvalStatus == 'rejected';
  bool get isApprovalApproved => approvalStatus == 'approved';

  bool hasRole(List<String> roles) {
    if (_user == null) return false;
    return roles.contains(_user!.roleKey);
  }

  Future<void> init(String apiBaseUrl) async {
    _api.setBaseUrl(apiBaseUrl);
    try {
      final storedUser = await _authService.loadStoredUser();
      final storedToken = await _authService.loadStoredToken();

      // If sign-in completed while init was awaiting storage, do not override it.
      if (_status == AuthStatus.authenticated &&
          _user != null &&
          _token != null) {
        return;
      }

      if (storedUser != null && storedToken != null) {
        _user = storedUser;
        _token = storedToken;
        _api.setAuthToken(storedToken);
        _status = AuthStatus.authenticated;
      } else {
        _api.clearAuthToken();
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _api.clearAuthToken();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> signInWithGoogle() async {
    _error = null;
    notifyListeners();
    try {
      final result = await _authService.signInWithGoogle();
      _user = result.user;
      _token = result.token;
      _api.setAuthToken(result.token);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = friendlyErrorMessage(
        e,
        fallback: 'Could not sign in. Please try again.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _api.clearAuthToken();
    _user = null;
    _token = null;
    _error = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> refreshApprovalStatus({bool silent = false}) async {
    if (_status != AuthStatus.authenticated ||
        _token == null ||
        _user == null) {
      return;
    }

    if (!silent && _error != null) {
      _error = null;
      notifyListeners();
    }

    try {
      final me = await _api.get<Map<String, dynamic>>('/auth/me');
      final merged = {..._user!.toJson(), ...me};
      final updatedUser = User.fromJson(merged);
      final hasChanged =
          updatedUser.approvalStatus != _user!.approvalStatus ||
          updatedUser.rejectionReason != _user!.rejectionReason ||
          updatedUser.roleKey != _user!.roleKey;

      _user = updatedUser;
      await _authService.saveStoredUser(_user!);
      if (hasChanged || (!silent && _error != null)) {
        notifyListeners();
      }
    } catch (e) {
      final message = friendlyErrorMessage(e);
      if (message.contains('401')) {
        await signOut();
        return;
      }
      final errorChanged = _error != message;
      _error = message;
      if (!silent || errorChanged) {
        notifyListeners();
      }
    }
  }

  void handleUnauthorized() {
    _api.clearAuthToken();
    _user = null;
    _token = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
