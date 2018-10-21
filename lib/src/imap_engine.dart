part of imap_client;

class ImapEngine {

  /// The socket used for communication with the imap server
  Socket _socket;

  /// A buffer for the imap server's responses
  ImapBuffer _buffer;

  ImapEngine(Socket _connection) {
    _socket = _connection;
    _socket.listen((response) {
      if (_isLoggerActive) _logger.info("S: " + String.fromCharCodes(response));
    });
    _buffer = ImapBuffer.bindToStream(_socket);
  }
}