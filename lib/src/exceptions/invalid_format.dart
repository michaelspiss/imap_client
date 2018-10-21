part of imap_client;

class InvalidFormatException implements Exception {
  final String cause;

  const InvalidFormatException([this.cause]);

  @override
  String toString() => cause ?? 'InvalidFormatException';
}