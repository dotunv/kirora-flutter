import 'options.dart';
import 'json.dart';

/// Runs the app's `beforeSend` on one event: on a detached copy, once, synchronously. A throw, an
/// answer JSON cannot hold, or a tracking call made from inside the hook drops the event; only the
/// kind of failure is reported, never the event.
class BeforeSendRunner {
  BeforeSendRunner(this.hook, {required this.onDrop});

  final BeforeSend? hook;

  /// `dropped` (the app returned null), `threw`, `unserializable` or `re-entry`.
  final void Function(String reason) onDrop;

  bool _running = false;

  /// With [detached], [properties] and [context] are already this event's own JSON copies, so the
  /// hook is handed them without copying again.
  ({Map<String, Object?> properties, Map<String, Object?> context})? run(
    String name,
    Map<String, Object?> properties,
    Map<String, Object?> context, {
    bool detached = false,
  }) {
    final hook = this.hook;
    if (hook == null) return (properties: properties, context: context);
    if (_running) {
      onDrop('re-entry');
      return null;
    }
    _running = true;
    try {
      final answer = hook(BeforeSendEvent(
        name: name,
        properties: detached ? properties : jsonSnapshot(properties)! as Map<String, Object?>,
        context: detached ? context : jsonSnapshot(context)! as Map<String, Object?>,
      ));
      if (answer == null) {
        onDrop('dropped');
        return null;
      }
      return (
        properties: jsonSnapshot(answer.properties)! as Map<String, Object?>,
        context: jsonSnapshot(answer.context)! as Map<String, Object?>,
      );
    } on UnrepresentableValue {
      onDrop('unserializable');
      return null;
    } catch (_) {
      onDrop('threw');
      return null;
    } finally {
      _running = false;
    }
  }
}
