library bdaya_fcm_handler;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Specifies the notification source
/// OnMessage: messages from [FirebaseMessaging.onMessage]
/// OnMessageOpenedApp: messages from [FirebaseMessaging.onMessageOpenedApp]
/// OnBackgroundMessage: messages from [FirebaseMessaging.onBackgroundMessage]
enum NotificationSource { OnMessage, OnBackgroundMessage, OnMessageOpenedApp }

Future<void> _handleBackgroundNotifs(RemoteMessage message) async {
  final finder = fcmServiceFinder;
  if (finder != null) {
    finder()?._raiseEvent(NotificationSource.OnBackgroundMessage, message);
  }
}

/// assign this to find and call the FCM service
FCMService? Function()? fcmServiceFinder;

/// how the message listeners should look like
typedef NotificationHandlerFunc = void Function(
  NotificationSource src,
  RemoteMessage message,
);

/// Request FCM settings for web,iOs and macOs
typedef FCMRequestFunc = Future<NotificationSettings> Function();

/// 1: register this service using a DI package (e.g. GetX)
/// 2: set fcmServiceFinder to a function that returns the [FCMService] singleton (e.g. Get.find<FCMService>)
/// 3: register your listeners using [registerSubscriber]
/// 4: call [doInit] in your splash or onboarding screen
class FCMService {
  final Map<String, StreamSubscription> _streamSubs = {};

  final _notificationSubscribers = <NotificationHandlerFunc>{};

  void _raiseEvent(NotificationSource src, RemoteMessage message) {
    for (var sub in _notificationSubscribers) {
      sub(src, message);
    }
  }

  /// Convenience stream for [FirebaseMessaging.onTokenRefresh]
  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  /// Used to get the FCM token and logs the result
  Future<String?> getToken({String? vapidKey, bool logResult = true}) async {
    final token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
    if (!logResult) {
      final borders = "=================================================";
      print('$borders\n FCM Token received: ${(token ?? '--')}\n$borders');
    }
    return token;
  }

  /// Registers a notification subscriber
  void registerSubscriber(NotificationHandlerFunc handler) {
    _notificationSubscribers.add(handler);
  }

  /// unRegisters a notification subscriber
  void unregisterSubscriber(NotificationHandlerFunc handler) {
    _notificationSubscribers.remove(handler);
  }

  /// get current platform from
  /// ```dart
  /// Theme.of(context).platform
  /// ```
  /// or
  ///
  /// [defaultTargetPlatform]
  Future<RemoteMessage?> doInit({
    FCMRequestFunc? requestFunc,
    TargetPlatform? platform,
  }) async {
    platform ??= defaultTargetPlatform;
    bool canUseFCM = true &&
        platform != TargetPlatform.windows && //disable on windows and linux
        platform != TargetPlatform.linux;

    if (canUseFCM &&
        (kIsWeb ||
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS)) {
      final settings = await requestFunc?.call();
      if (settings != null) {
        print('User granted permission: ${settings.authorizationStatus}');
        if (settings.authorizationStatus == AuthorizationStatus.denied ||
            settings.authorizationStatus == AuthorizationStatus.notDetermined) {
          canUseFCM = false;
        }
      }
    }

    if (canUseFCM) {
      final initMessage = await FirebaseMessaging.instance.getInitialMessage();

      _streamSubs['onMessage'] = FirebaseMessaging.onMessage.listen((event) {
        _raiseEvent(NotificationSource.OnMessage, event);
      });
      FirebaseMessaging.onBackgroundMessage(_handleBackgroundNotifs);
      _streamSubs['onMessageOpenedApp'] =
          FirebaseMessaging.onMessageOpenedApp.listen((event) {
        _raiseEvent(NotificationSource.OnMessageOpenedApp, event);
      });
      return initMessage;
    } else {
      return null;
    }
  }

  /// Call this to dispose the service, cancels all streams and removes all subscribers
  Future<void> onClose() async {
    for (var item in _streamSubs.values) {
      await item.cancel();
    }
    _notificationSubscribers.clear();
  }
}
