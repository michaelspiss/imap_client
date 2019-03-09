part of imap_client;

/// Thrown by ImapBuffer when trying to read type that doesn't match actual type
class InvalidFormatException implements Exception {
  final String cause;

  const InvalidFormatException([this.cause]);

  @override
  String toString() => cause ?? 'InvalidFormatException';
}
