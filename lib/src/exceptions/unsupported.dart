part of imap_client;

/// Thrown when a command is used that is not supported by the server
class UnsupportedException implements Exception {
  final String cause;

  const UnsupportedException([this.cause]);

  @override
  String toString() => cause ?? 'UnsupportedException';
}
