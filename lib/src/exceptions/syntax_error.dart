part of imap_client;

/// Thrown by [ImapCommand] or [ImapEngine] when the response has a syntax error
class SyntaxErrorException implements Exception {
  final String cause;

  const SyntaxErrorException([this.cause]);

  @override
  String toString() => cause ?? 'SyntaxErrorException';
}
