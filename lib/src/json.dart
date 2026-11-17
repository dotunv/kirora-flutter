// JSON values as the SDK copies them at capture.

import 'dart:collection';

String toIso(DateTime time) => time.toUtc().toIso8601String();

/// A value that cannot be represented faithfully as JSON: the event carrying it is dropped.
class UnrepresentableValue implements Exception {
  UnrepresentableValue(this.category);

  /// What kind of value it was (`cycle`, `number`, `key`, `object`, `toJson`, `depth`), never the
  /// value.
  final String category;

  @override
  String toString() => 'UnrepresentableValue($category)';
}

/// A JSON copy of [value], taken at capture, as Dart's standard encoder would write it: a
/// `DateTime` becomes its ISO 8601 string and an object with `toJson()` its result. A cycle, a
/// non-finite number, a non-string map key, an object without `toJson()`, or a `toJson()` that
/// throws, throws [UnrepresentableValue] and nothing else.
Object? jsonSnapshot(Object? value) => _snapshot(value, 0, LinkedHashSet<Object>.identity());

/// [path] holds the maps, lists and objects being copied above this value: one met again is a cycle.
/// The same value reached twice by different paths is copied twice, as the encoder would.
Object? _snapshot(Object? value, int depth, Set<Object> path) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) throw UnrepresentableValue('number');
    return value;
  }
  if (value is DateTime) return toIso(value);
  if (depth >= 64) throw UnrepresentableValue('depth');
  if (!path.add(value)) throw UnrepresentableValue('cycle');
  try {
    if (value is Map) {
      final copy = <String, Object?>{};
      for (final e in value.entries) {
        final key = e.key;
        if (key is! String) throw UnrepresentableValue('key');
        copy[key] = _snapshot(e.value, depth + 1, path);
      }
      return copy;
    }
    if (value is Iterable) return [for (final v in value) _snapshot(v, depth + 1, path)];
    final Object? json;
    try {
      json = (value as dynamic).toJson();
    } on NoSuchMethodError {
      throw UnrepresentableValue('object');
    } catch (_) {
      // The app's own toJson() failed: the event is dropped, never the app's call.
      throw UnrepresentableValue('toJson');
    }
    return _snapshot(json, depth + 1, path);
  } finally {
    path.remove(value);
  }
}
