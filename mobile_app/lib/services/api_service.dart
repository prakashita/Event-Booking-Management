import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();
  String? _baseUrl;
  String? _cachedToken;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    _setupInterceptors();
  }

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _dio.options.baseUrl = '$_baseUrl${AppConstants.apiBase}';
  }

  void setAuthToken(String? token) {
    final normalized = token?.trim();
    _cachedToken = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
  }

  void clearAuthToken() {
    _cachedToken = null;
  }

  String? getToken() => _cachedToken;
  String? get baseUrl => _baseUrl;

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Keep in-memory token aligned with persisted token to avoid
          // cross-account leakage after sign out / sign in.
          final storedToken = await _storage.read(key: AppConstants.tokenKey);
          if (storedToken != _cachedToken) {
            _cachedToken = storedToken;
          }

          final token = _cachedToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }

          final isMultipartRequest =
              options.data is FormData ||
              (options.contentType?.toLowerCase().contains(
                    'multipart/form-data',
                  ) ??
                  false);

          if (isMultipartRequest) {
            options.headers.remove('Content-Type');
          } else {
            options.headers['Content-Type'] = 'application/json';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            _cachedToken = null;
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.get(
      path,
      queryParameters: params,
      options: headers == null ? null : Options(headers: headers),
    );
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.post(
      path,
      data: data,
      options: headers == null ? null : Options(headers: headers),
    );
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.patch(
      path,
      data: data,
      options: headers == null ? null : Options(headers: headers),
    );
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.put(
      path,
      data: data,
      options: headers == null ? null : Options(headers: headers),
    );
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.delete(
      path,
      data: data,
      options: headers == null ? null : Options(headers: headers),
    );
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<Uint8List> getBytes(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final resp = await _dio.get<List<int>>(
      path,
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = resp.data ?? const <int>[];
    return Uint8List.fromList(data);
  }

  Future<T> postMultipart<T>(
    String path,
    FormData formData, {
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.post(
      path,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  String? get wsBaseUrl {
    if (_baseUrl == null) return null;
    return _baseUrl!
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }
}
