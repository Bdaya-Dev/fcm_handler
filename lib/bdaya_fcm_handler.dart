library bdaya_fcm_handler;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get.dart';
import 'package:rxdart/rxdart.dart' as rx;

enum NotificationSource { OnMessage, OnBackgroundMessage, OnMessageOpenedApp }

Future<void> handleBackgroundNotifs(RemoteMessage message) async {
  if (Get.isRegistered<FCMService>())
    Get.find<FCMService>()
        ._raiseEvent(NotificationSource.OnBackgroundMessage, message);
}

class CombinedUserToken {
  final String userId;
  final String token;

  CombinedUserToken._(this.userId, this.token);
}

typedef NotificationHandlerFunc = void Function(
    NotificationSource src, RemoteMessage message);

/// First: register this service (using normal [Get.put])
/// Second: register your listeners using [registerSubscriber]
/// Third: call doInit
class FCMService extends GetxService {
  final Map<String, StreamSubscription> _streamSubs = {};

  final _notificationSubscribers = <NotificationHandlerFunc>{};

  /// A helper stream that combines the current user with its token
  // Stream<CombinedUserToken> get combinedAuthTokenStream =>
  //     rx.Rx.combineLatest2<User, String, CombinedUserToken>(
  //       FirebaseAuth.instance.authStateChanges(),
  //       FirebaseMessaging.instance.onTokenRefresh,
  //       (a, b) => CombinedUserToken._(a.uid, b),
  //     );

  void _raiseEvent(NotificationSource src, RemoteMessage message) {
    for (var sub in _notificationSubscribers) {
      sub(src, message);
    }
  }

  /// Registers a notification subscriber
  void registerSubscriber(NotificationHandlerFunc handler) {
    _notificationSubscribers.add(handler);
  }

  /// unRegisters a notification subscriber
  void unregisterSubscriber(NotificationHandlerFunc handler) {
    _notificationSubscribers.remove(handler);
  }

  Future<RemoteMessage> doInit() async {
    // final settings = await FirebaseMessaging.instance.requestPermission(
    //   alert: true,
    //   announcement: false,
    //   badge: true,
    //   carPlay: false,
    //   criticalAlert: false,
    //   provisional: false,
    //   sound: true,
    // );

    final initMessage = await FirebaseMessaging.instance.getInitialMessage();

    _streamSubs['onMessage'] = FirebaseMessaging.onMessage.listen((event) {
      _raiseEvent(NotificationSource.OnMessage, event);
    });
    FirebaseMessaging.onBackgroundMessage(handleBackgroundNotifs);
    _streamSubs['onMessageOpenedApp'] =
        FirebaseMessaging.onMessageOpenedApp.listen((event) {
      _raiseEvent(NotificationSource.OnMessageOpenedApp, event);
    });
    return initMessage;
  }

  @override
  void onClose() async {
    for (var item in _streamSubs.values) {
      await item.cancel();
    }
    _notificationSubscribers.clear();
    super.onClose();
  }
}
