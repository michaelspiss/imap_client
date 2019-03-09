part of imap_client;

/// Thrown by ImapEngine when command queue is empty or command is missing
class MissingCommandException implements Exception {
  final String cause;

  const MissingCommandException([this.cause]);

  @override
  String toString() => cause ?? 'MissingCommandException';
}
