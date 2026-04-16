import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

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

  bool hasRole(List<String> roles) {
    if (_user == null) return false;
    return roles.contains(_user!.roleKey);
  }

  Future<void> init(String apiBaseUrl) async {
    _api.setBaseUrl(apiBaseUrl);
    try {
      final storedUser = await _authService.loadStoredUser();
      final storedToken = await _authService.loadStoredToken();
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
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _api.clearAuthToken();
    _user = null;
    _token = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void handleUnauthorized() {
    _api.clearAuthToken();
    _user = null;
    _token = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
