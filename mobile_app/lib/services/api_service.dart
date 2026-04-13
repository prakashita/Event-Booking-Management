import 'package:dio/dio.dart';
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

  String? getToken() => _cachedToken;

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          String? token = _cachedToken;
          token ??= await _storage.read(key: AppConstants.tokenKey);
          if (token != null) {
            _cachedToken = token;
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Content-Type'] = 'application/json';
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
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.get(path, queryParameters: params);
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.post(path, data: data);
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> patch<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? parser,
  }) async {
    final resp = await _dio.patch(path, data: data);
    return parser != null ? parser(resp.data) : resp.data as T;
  }

  Future<T> delete<T>(String path, {T Function(dynamic)? parser}) async {
    final resp = await _dio.delete(path);
    return parser != null ? parser(resp.data) : resp.data as T;
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
