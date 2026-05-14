import 'package:dio/dio.dart';

String friendlyErrorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error == null) return fallback;

  if (error is DioException) {
    return _messageForDioException(error, fallback);
  }

  final text = _cleanErrorText(error.toString());
  if (text.isEmpty) return fallback;

  final lower = text.toLowerCase();
  if (_looksLikeConnectionIssue(lower)) {
    return 'Please check your internet connection.';
  }
  if (lower.contains('cancel')) {
    return 'Action cancelled.';
  }
  if (lower.contains('api exception: 10')) {
    return 'Google sign-in is not set up correctly.';
  }
  if (lower.contains('unauthorized') || lower.contains('401')) {
    return 'Please sign in again.';
  }
  if (lower.contains('forbidden') || lower.contains('403')) {
    return 'You do not have permission to do that.';
  }
  if (lower.contains('not found') || lower.contains('404')) {
    return 'We could not find that item.';
  }
  if (lower.contains('validation') || lower.contains('422')) {
    return 'Please check the details and try again.';
  }

  return _isSafeUserMessage(text) ? text : fallback;
}

String _messageForDioException(DioException error, String fallback) {
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout) {
    return 'The request timed out. Please try again.';
  }
  if (error.type == DioExceptionType.connectionError) {
    return 'Please check your internet connection.';
  }
  if (error.type == DioExceptionType.cancel) {
    return 'Action cancelled.';
  }

  final status = error.response?.statusCode;
  final detail = _cleanErrorText(_detailText(error.response?.data));
  if (status == 403) {
    final approvalMessage = _approvalMessage(error);
    if (approvalMessage != null) return approvalMessage;
  }
  if (status != null && status < 500 && _isSafeUserMessage(detail)) {
    return detail;
  }

  switch (status) {
    case 400:
      return 'Please check the details and try again.';
    case 401:
      return 'Please sign in again.';
    case 403:
      return 'You do not have permission to do that.';
    case 404:
      return 'We could not find that item.';
    case 409:
      return 'This item was already updated. Please refresh and try again.';
    case 413:
      return 'The selected file is too large.';
    case 422:
      return 'Please check the details and try again.';
    case 429:
      return 'Too many attempts. Please wait and try again.';
  }

  if (status != null && status >= 500) {
    return 'Server is having trouble. Please try again later.';
  }

  final text = _cleanErrorText(error.message ?? '');
  if (text.isEmpty) return fallback;
  return _isSafeUserMessage(text) ? text : fallback;
}

String? _approvalMessage(DioException error) {
  final detail = _detailText(error.response?.data).toLowerCase();
  if (detail.contains('pending')) {
    return 'Your account is waiting for approval.';
  }
  if (detail.contains('reject')) {
    return 'Your account was not approved.';
  }
  return null;
}

String _detailText(dynamic data) {
  if (data is Map) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List) return detail.join(' ');
  }
  if (data is String) return data;
  return '';
}

String _cleanErrorText(String text) {
  return text
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^DioException\s*\[[^\]]+\]:\s*'), '')
      .trim();
}

bool _looksLikeConnectionIssue(String lower) {
  return lower.contains('socketexception') ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('failed host lookup') ||
      lower.contains('cannot reach server');
}

bool _isSafeUserMessage(String text) {
  if (text.length > 90) return false;
  final lower = text.toLowerCase();
  const debugMarkers = [
    'dioexception',
    'socketexception',
    'stacktrace',
    'traceback',
    'xmlhttprequest',
    'https://',
    'http://',
    'package:',
    '{',
    '}',
    '[',
    ']',
  ];
  return !debugMarkers.any(lower.contains);
}
