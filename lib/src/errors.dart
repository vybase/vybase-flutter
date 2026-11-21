/// Thrown for every API error. Branch on [code] (stable), not on [message].
class VybaseException implements Exception {
  VybaseException(this.code, this.message, {this.status = 0});

  /// e.g. `email_taken`, `invalid_credentials`, `otp_invalid`, `rate_limited`, `network_error`.
  final String code;
  final String message;

  /// HTTP status, or 0 when the request never reached the server.
  final int status;

  @override
  String toString() => 'VybaseException($code, $status): $message';
}
