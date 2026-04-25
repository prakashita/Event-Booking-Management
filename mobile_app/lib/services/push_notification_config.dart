import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class PushNotificationConfig {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const String _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const String _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.namaah.mobile_app',
  );
  static const String _iosClientId = String.fromEnvironment(
    'FIREBASE_IOS_CLIENT_ID',
  );

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static FirebaseOptions? get currentOptions {
    if (!isSupportedPlatform) return null;

    final appId = defaultTargetPlatform == TargetPlatform.iOS
        ? _iosAppId
        : _androidAppId;
    if (appId.trim().isEmpty ||
        _apiKey.trim().isEmpty ||
        _messagingSenderId.trim().isEmpty ||
        _projectId.trim().isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      storageBucket: _storageBucket.trim().isEmpty ? null : _storageBucket,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
          ? (_iosBundleId.trim().isEmpty ? null : _iosBundleId)
          : null,
      iosClientId: defaultTargetPlatform == TargetPlatform.iOS
          ? (_iosClientId.trim().isEmpty ? null : _iosClientId)
          : null,
    );
  }

  static String get currentPlatformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unsupported';
    }
  }
}
