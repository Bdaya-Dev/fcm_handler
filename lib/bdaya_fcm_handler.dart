library bdaya_fcm_handler;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:rxdart/rxdart.dart';

enum NotificationSource {
  InitialMessage,
  OnMessage,
  OnBackgroundMessage,
  OnMessageOpenedApp
}

Future<void> handleBackgroundNotifs(RemoteMessage message) async {
  Get.find<FCMServiceBase>()
      .raiseEvent(NotificationSource.OnBackgroundMessage, message);
}

class CombinedUserToken {
  final String userId;
  final String token;

  CombinedUserToken(this.userId, this.token);
}

typedef NotificationHandlerFunc = void Function(
    NotificationSource src, RemoteMessage message);

/// First: register this service (using normal [Get.put])
/// Second: register your listeners using [registerSubscriber]
/// Third: call doInit
class FCMServiceBase extends GetxService {
  final Map<String, StreamSubscription> _streamSubs = {};

  final _notificationSubscribers = <NotificationHandlerFunc>{};

  /// A helper stream that combines the current user with its token
  Stream get combinedAuthTokenStream => FirebaseAuth.instance
          .authStateChanges()
          .switchMap<CombinedUserToken>((user) {
        if (user == null) {
          return Stream.value(null);
        } else {
          return FirebaseMessaging.instance.onTokenRefresh
              .map((token) => CombinedUserToken(user.uid, token));
        }
      });

  void raiseEvent(NotificationSource src, RemoteMessage message) {
    for (var sub in _notificationSubscribers) {
      sub(src, message);
    }
  }

  void registerSubscriber(NotificationHandlerFunc handler) {
    _notificationSubscribers.add(handler);
  }

  void unregisterSubscriber(NotificationHandlerFunc handler) {
    _notificationSubscribers.remove(handler);
  }

  Future<void> doInit() async {
    final initMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initMessage != null) {
      raiseEvent(NotificationSource.InitialMessage, initMessage);
    }
    _streamSubs['onMessage'] = FirebaseMessaging.onMessage.listen((event) {
      raiseEvent(NotificationSource.OnMessage, event);
    });
    //TODO: reenable background messaging after they fix it
    //FirebaseMessaging.onBackgroundMessage(handleBackgroundNotifs);
    _streamSubs['onMessageOpenedApp'] =
        FirebaseMessaging.onMessageOpenedApp.listen((event) {
      raiseEvent(NotificationSource.OnMessageOpenedApp, event);
    });
  }

  @override
  @mustCallSuper
  void onClose() async {
    for (var item in _streamSubs.values) {
      await item.cancel();
    }
    _notificationSubscribers.clear();
    super.onClose();
  }
}
