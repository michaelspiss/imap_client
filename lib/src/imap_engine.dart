part of imap_client;

class ImapEngine {
  /// The socket used for communication with the imap server
  Socket _socket;

  /// A buffer for the imap server's responses
  ImapBuffer _buffer;

  ImapEngine(Socket _connection) {
    _socket = _connection;
    _buffer = new ImapBuffer();

    _socket.listen(
        (response) {
          _buffer.addAll(response);
          if (_isLoggerActive)
            _logger.info("S: " + String.fromCharCodes(response));
        },
        cancelOnError: true,
        onDone: () {
          _logger.info("Connection has been terminated by the server.");
          _socket.destroy();
        });
  }
}
