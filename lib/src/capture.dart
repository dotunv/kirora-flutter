import 'before_send.dart';
import 'json.dart';
import 'options.dart';

/// What happens to an event the app tracks before it leaves Dart: its properties copied as JSON at
/// the call ([copy]), then `beforeSend` ([release]) once tracking is known to be allowed. Shared by
/// the SDK and `KiroraMock`, so app tests see what production sends. Neither step throws.
class EventCapture {
  EventCapture(BeforeSend? hook, {required void Function(String message) onError})
      : _onError = onError,
        _runner = BeforeSendRunner(hook, onDrop: (reason) {
          if (reason != 'dropped') onError('Event dropped: beforeSend failed ($reason).');
        });

  final void Function(String message) _onError;
  final BeforeSendRunner _runner;

  bool get hasHook => _runner.hook != null;

  /// `track()`'s copy, taken at the call: null when a property cannot be sent as JSON.
  PendingEvent? copy(String name, Map<String, Object?>? properties) {
    try {
      final props = jsonSnapshot(properties ?? const <String, Object?>{})! as Map<String, Object?>;
      return PendingEvent._(name, props, hadProperties: properties != null, screen: false);
    } on UnrepresentableValue catch (e) {
      _onError('Event dropped: a property cannot be sent as JSON (${e.category}).');
    } catch (e) {
      _onError('Event dropped: ${e.runtimeType}.');
    }
    return null;
  }

  /// `trackScreenView()`'s event, as `Screen Viewed`.
  PendingEvent screen(String name) =>
      PendingEvent._(screenViewed, {'name': name}, hadProperties: true, screen: true);

  /// Runs `beforeSend` on [event]: null when it is dropped. For an event the app tracked,
  /// [CapturedEvent.properties] is null when the app gave none and the hook added none; for a screen
  /// view, null when it goes unchanged (the native SDK's own screen view).
  CapturedEvent? release(PendingEvent event) {
    if (event.screen && !hasHook) return const CapturedEvent(null);
    try {
      // The copy is this event's own, so the hook gets it without a second copy.
      final kept = _runner.run(event.name, event.properties, <String, Object?>{}, detached: true);
      if (kept == null) return null;
      final p = kept.properties;
      if (event.screen) return CapturedEvent(p.length == 1 && p['name'] == event.properties['name'] ? null : p);
      return CapturedEvent(!event.hadProperties && p.isEmpty ? null : p);
    } catch (e) {
      _onError('Event dropped: ${e.runtimeType}.');
      return null;
    }
  }

  /// [copy] then [release], for a caller that knows tracking is allowed now.
  CapturedEvent? track(String name, Map<String, Object?>? properties) {
    final pending = copy(name, properties);
    return pending == null ? null : release(pending);
  }

  CapturedEvent? screenView(String name) => release(screen(name));

  static const screenViewed = 'Screen Viewed';
}

/// An event copied at the call, waiting for `beforeSend`.
class PendingEvent {
  PendingEvent._(this.name, this.properties, {required this.hadProperties, required this.screen});

  final String name;
  final Map<String, Object?> properties;
  final bool hadProperties;
  final bool screen;
}

class CapturedEvent {
  const CapturedEvent(this.properties);

  final Map<String, Object?>? properties;
}
