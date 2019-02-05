part of imap_client;

/// Gets instantiated when [ImapBuffer] did not receive the requested char yet
///
/// See implementation in [ImapBuffer] _getCharCode() method
class _BufferAwaiter {
  final Completer completer;
  final int awaitedPosition;

  _BufferAwaiter(this.completer, this.awaitedPosition);
}
