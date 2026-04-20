import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import '../constants/app_constants.dart';
import '../models/models.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final _storage = const FlutterSecureStorage();
  final _api = ApiService();
  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile', 'openid'],
    clientId: kIsWeb && AppConstants.googleClientId.isNotEmpty
        ? AppConstants.googleClientId
        : null,
    serverClientId: kIsWeb
        ? null
        : (AppConstants.googleServerClientId.isNotEmpty
              ? AppConstants.googleServerClientId
              : (AppConstants.googleClientId.isNotEmpty
                    ? AppConstants.googleClientId
                    : null)),
  );

  AuthService._internal();

  Future<User?> loadStoredUser() async {
    final userJson = await _storage.read(key: AppConstants.userKey);
    if (userJson == null) return null;
    try {
      return User.fromJson(jsonDecode(userJson));
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadStoredToken() async {
    return _storage.read(key: AppConstants.tokenKey);
  }

  Future<void> saveStoredUser(User user) async {
    await _storage.write(
      key: AppConstants.userKey,
      value: jsonEncode(user.toJson()),
    );
  }

  Future<({User user, String token})> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) throw Exception('Google sign-in cancelled');

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Could not obtain Google ID token');
      }

      final response = await _api.post<Map<String, dynamic>>(
        '/auth/google',
        data: {'token': idToken},
      );

      final token = response['access_token'] as String;
      final user = User.fromJson(response['user'] as Map<String, dynamic>);

      await Future.wait([
        _storage.write(key: AppConstants.tokenKey, value: token),
        _storage.write(
          key: AppConstants.userKey,
          value: jsonEncode(user.toJson()),
        ),
      ]);

      return (user: user, token: token);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw Exception(
          'Cannot reach server. Set API_BASE_URL to your backend host (e.g. http://10.0.2.2:8000 for Android emulator).',
        );
      }

      final status = e.response?.statusCode;
      final data = e.response?.data;
      final detail = data is Map<String, dynamic>
          ? (data['detail']?.toString())
          : null;

      if (status == 403 && detail != null && detail.isNotEmpty) {
        throw Exception(detail);
      }
      if (status == 401) {
        throw Exception(
          'Google token validation failed. Please try signing in again.',
        );
      }
      if (status == 500) {
        throw Exception(
          'Server auth configuration is incomplete. Contact admin.',
        );
      }

      throw Exception(detail ?? 'Login failed (${status ?? 'network error'}).');
    } on Exception catch (e) {
      final text = e.toString();
      if (text.contains('ApiException: 10')) {
        throw Exception(
          'Google Sign-In blocked by Android OAuth config (ApiException 10). Verify package name and SHA-1 in Google Cloud.',
        );
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    
    try {
      await _storage.delete(key: AppConstants.tokenKey);
    } catch (_) {}
    
    try {
      await _storage.delete(key: AppConstants.userKey);
    } catch (_) {}
  }
}
