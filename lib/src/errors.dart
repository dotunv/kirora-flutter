/// What the SDK throws: [UserTokenError], [KiroraApiError], or this type itself for a setup
/// problem (an `apiUrl` that isn't an address, say). `track()` throws nothing; `logout()` never fails.
class KiroraError implements Exception {
  KiroraError(this.message);

  final String message;

  @override
  String toString() => 'KiroraError: $message';
}

/// `fetchUserToken` failed, or there is no way to get a token.
class UserTokenError extends KiroraError {
  UserTokenError(super.message, [this.cause]);

  final Object? cause;

  @override
  String toString() => 'UserTokenError: $message';
}

/// Kirora refused a call. `identify()` throws it with status 401 when Kirora refuses even a fresh
/// token.
class KiroraApiError extends KiroraError {
  KiroraApiError(this.status, this.code, super.message, {this.retryAfterMs});

  /// The HTTP status.
  final int status;

  /// Kirora's error code, when it sent one (`PLAN_FEATURE_UNAVAILABLE`).
  final String? code;

  /// From the `Retry-After` header, when there was one.
  final int? retryAfterMs;

  /// 408, 425, 429 and 5xx: the same call may succeed later.
  bool get retryable => status == 408 || status == 425 || status == 429 || status >= 500;

  @override
  String toString() => 'KiroraApiError($status${code == null ? '' : ', $code'}): $message';
}
