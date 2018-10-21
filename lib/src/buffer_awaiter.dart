part of imap_client;

/// Gets instantiated when [ImapBuffer] did not receive the requested char yet
class _BufferAwaiter {
  final Completer completer;
  final int awaitedPosition;

  _BufferAwaiter(this.completer, this.awaitedPosition);
}
