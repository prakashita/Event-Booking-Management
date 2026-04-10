import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session.dart';

class ApiClient {
  ApiClient(this.session);

  final AppSession session;

  String get _base =>
      '${session.baseUrl.replaceAll(RegExp(r'/$'), '')}/api/v1';

  Future<dynamic> get(String path) => _req('GET', path);

  Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _req('POST', path, body: body);

  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _req('PATCH', path, body: body);

  Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _req('PUT', path, body: body);

  Future<dynamic> delete(String path) => _req('DELETE', path);

  Future<dynamic> _req(
      String method,
      String path, {
        Map<String, dynamic>? body,
      }) async {
    final url = path.startsWith('http') ? path : '$_base$path';
    final uri = Uri.parse(url);

    final request = http.Request(method, uri);
    request.headers['Authorization'] = 'Bearer ${session.token}';
    request.headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = response.body;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail =
      data is Map<String, dynamic> ? data['detail']?.toString() : null;
      throw ApiException(
        detail ?? 'Request failed (${response.statusCode})',
        response.statusCode,
      );
    }

    return data;
  }
}

class ApiException implements Exception {
  const ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  if (v is Map && v.containsKey('data')) {
    final d = v['data'];
    if (d is List) return d;
  }
  return const [];
}
