part of imap_client;

/// Thrown by ImapEngine when command queue is empty or command is missing
class StateException implements Exception {
  final String cause;

  const StateException([this.cause]);

  @override
  String toString() => cause ?? 'StateException';
}
