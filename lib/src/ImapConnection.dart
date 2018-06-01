part of ImapClient;

class ImapConnection {

  /// The socket used for communication
  Socket _connection;

  /// Indicates whether the connection is currently open or not
  bool _isOpen = false;

  /// Read-only access to the isOpen state
  bool get isOpen => _isOpen;

  /// Sets up the socket and connects to the host
  ///
  /// Returns a future that completes when the connection is established and
  /// calls the [responseHandler] each time the new data arrives.
  Future<Socket> connect(String host, int port, bool secure,
      Function responseHandler) {
    Future<Socket> futureSocket = secure ? SecureSocket.connect(host, port)
        : Socket.connect(host, port);

    return futureSocket.then((socket) {
      _connection = socket;
      _isOpen = true;
      _connection.listen(responseHandler,
        cancelOnError: true,
        onDone: () {
          _connection.destroy();
          _isOpen = false;
        });
    });
  }

  /// Sends a command to the server
  ///
  /// Each [command] to the server needs a unique [tag]. There can be zero to
  /// unlimited [parameters]. Throws a [SocketException] if the connection is
  /// not open.
  void sendCommand(String tag, String command, [String parameters = '']) {
    if(_isOpen) {
      // MUST end with CRLF [RFC3501], trim removes space if no parameters given
      _connection.write('$tag $command $parameters'.trim() + '\r\n');
    } else {
      throw new SocketException('Socket is closed.');
    }
  }
}