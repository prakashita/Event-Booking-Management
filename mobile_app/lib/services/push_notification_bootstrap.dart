import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_notification_config.dart';

class PushNotificationBootstrap {
  static Future<bool> ensureInitialized() async {
    final options = PushNotificationConfig.currentOptions;
    if (options == null) {
      if (kDebugMode) {
        print(
          'PushNotificationBootstrap: Firebase options missing for this platform, skipping push setup',
        );
      }
      return false;
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    return true;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationBootstrap.ensureInitialized();
}
