/// A read-only snapshot of the SDK's state, for an app's support and debug screens. Never sent
/// anywhere. The native SDK is behind an async channel, so state is read, not observed.
class KiroraState {
  const KiroraState({
    required this.isInitialized,
    required this.isIdentified,
    required this.deviceId,
    required this.sessionId,
    required this.pushToken,
    required this.trackingConsent,
    required this.pushConsent,
    required this.queuedEventCount,
  });

  /// The client is set up and not destroyed.
  final bool isInitialized;

  /// A user is signed in.
  final bool isIdentified;

  /// The id sent in `context.device.id`, or null when there is none (deleted after tracking
  /// consent was withdrawn, say).
  final String? deviceId;

  /// The current visit, or null.
  final String? sessionId;

  /// The token in the device's current registration (APNs or FCM), or null when it is not
  /// registered. Not the platform's raw token.
  final String? pushToken;

  /// Whether behavioural tracking is allowed now.
  final bool trackingConsent;

  /// The signed-in user's marketing push choice, as this device last recorded it with Kirora
  /// (`setPushConsent`). False when there is none; cleared at `logout()` and when another user
  /// signs in.
  final bool pushConsent;

  /// Events waiting on the device.
  final int queuedEventCount;
}
