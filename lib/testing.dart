/// A stand-in for [Kirora] in your app's own tests, where there is no native SDK.
///
/// ```dart
/// import 'package:kirora_flutter/testing.dart';
///
/// final kirora = KiroraMock();
/// await myCheckout(kirora);
/// expect(kirora.tracked.single.name, 'Order Completed');
/// ```
///
/// Pass it wherever your app takes a [Kirora]. It records every call, answers with values you can
/// set, sends nothing and never throws unless you ask it to. Tracked events are handled as the real
/// SDK handles them: properties copied as JSON when tracked, `beforeSend` applied, and an event
/// with a value JSON can't hold dropped.
library;

import 'dart:async';

import 'package:flutter/services.dart' show MethodCall;

import 'kirora_flutter.dart';
import 'src/capture.dart';

export 'kirora_flutter.dart';

/// An event the app tracked through a [KiroraMock].
class TrackedEvent {
  const TrackedEvent(this.name, this.properties);

  final String name;
  final Map<String, Object?>? properties;

  @override
  String toString() => 'TrackedEvent($name, $properties)';
}

class KiroraMock implements Kirora {
  KiroraMock([this.options = const KiroraOptions(clientKey: 'kirora_pk_mock')]);

  @override
  final KiroraOptions options;

  /// Every call, in order, as `MethodCall(method, arguments)`.
  final calls = <MethodCall>[];

  /// The events tracked with [track] and [trackScreenView], as the SDK would store them: copied at
  /// capture, after `options.beforeSend`.
  final tracked = <TrackedEvent>[];

  late final _capture = EventCapture(options.beforeSend, onError: (_) {});

  @override
  bool isAvailable = true;

  /// Thrown by the next [identify] calls while set (a [UserTokenError], say).
  KiroraError? identifyError;

  /// Thrown by the next [setPushConsent] calls while set (a [KiroraApiError], say).
  KiroraError? pushConsentError;

  /// What [requestPushPermission] answers.
  PushPermission pushPermission = PushPermission.granted;

  /// What [getPushStatus] answers.
  PushStatus pushStatus = PushStatus.enabled;

  bool isIdentified = false;
  /// Off until [setTrackingConsent] when `options.requireTrackingConsent` is set, as in the SDK.
  late bool trackingConsent = !options.requireTrackingConsent;
  bool pushConsent = false;
  String? deviceId = 'mock-device';
  String? sessionId;
  String? pushToken;

  final _clicks = StreamController<NotificationData>.broadcast();
  final _received = StreamController<NotificationData>.broadcast();

  /// Delivers a tap to [onNotificationClicked] listeners, as the native SDK would.
  void simulateNotificationClick(NotificationData data) => _clicks.add(data);

  /// Delivers an arriving push to [onNotificationReceived] listeners.
  void simulateNotificationReceived(NotificationData data) => _received.add(data);

  void _record(String method, [Object? arguments]) => calls.add(MethodCall(method, arguments));

  @override
  Future<void> identify([String? token]) async {
    _record('identify', {'token': token});
    final error = identifyError;
    if (error != null) throw error;
    isIdentified = true;
  }

  @override
  Future<void> logout() async {
    _record('logout');
    isIdentified = false;
    pushConsent = false;
  }

  @override
  void track(String name, [Map<String, Object?>? properties]) {
    _record('track', {'name': name});
    // As in the SDK: nothing is collected without consent, and beforeSend never sees it.
    if (!trackingConsent) return;
    final event = _capture.track(name, properties);
    if (event != null) tracked.add(TrackedEvent(name, event.properties));
  }

  @override
  void trackScreenView(String name) {
    _record('trackScreenView', {'name': name});
    if (!trackingConsent) return;
    final event = _capture.screenView(name);
    if (event != null) tracked.add(TrackedEvent(EventCapture.screenViewed, event.properties ?? {'name': name}));
  }

  @override
  void setTrackingConsent(bool granted) {
    _record('setTrackingConsent', {'granted': granted});
    trackingConsent = granted;
  }

  @override
  Future<void> setPushConsent(bool granted) async {
    _record('setPushConsent', {'granted': granted});
    final error = pushConsentError;
    if (error != null) throw error;
    pushConsent = granted;
  }

  @override
  Future<PushPermission> requestPushPermission() async {
    _record('requestPushPermission');
    return pushPermission;
  }

  @override
  Future<PushStatus> getPushStatus() async {
    _record('getPushStatus');
    return pushStatus;
  }

  @override
  Future<void> setPushEnabled(bool enabled) async {
    _record('setPushEnabled', {'enabled': enabled});
  }

  @override
  void destroy() => _record('destroy');

  @override
  Future<void> flush() async => _record('flush');

  @override
  Future<KiroraState> getState() async {
    _record('getState');
    return KiroraState(
      isInitialized: true,
      isIdentified: isIdentified,
      deviceId: deviceId,
      sessionId: sessionId,
      pushToken: pushToken,
      trackingConsent: trackingConsent,
      pushConsent: pushConsent,
      queuedEventCount: 0,
    );
  }

  @override
  Stream<NotificationData> get onNotificationClicked => _clicks.stream;

  @override
  Stream<NotificationData> get onNotificationReceived => _received.stream;

  @override
  void onNewPushToken(String token) => _record('onNewPushToken', {'token': token});
}
