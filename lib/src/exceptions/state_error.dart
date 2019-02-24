part of imap_client;

/// Thrown by ImapEngine when command queue is empty or command is missing
class StateErrorException implements Exception {
  final String cause;

  const StateErrorException([this.cause]);

  @override
  String toString() => cause ?? 'StateErrorException';
}
