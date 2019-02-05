part of imap_client;

/// Main point for interaction with the server
///
/// Handles commands that are not folder ("mailbox") specific and selects
class ImapServer {
  ImapEngine _engine;

  /// Host address the server is connected to
  String _host;

  String get host => _host;

  /// Port the server is connected to
  int _port;

  int get port => _port;

  /// If true, the communication with the server is encrypted
  bool _secure;

  bool get secure => _secure;

  /// Connects the server model to the actual server
  ///
  /// [host] and [port] define the server's address. If [secure] is true,
  /// a secure (ssl) socket will be used, an unencrypted one otherwise.
  Future<void> connect(String host, int port, bool secure) async {
    _host = host;
    _port = port;
    _secure = secure;

    _logger.info("Connecting to $host at port $port with secure mode " +
        (secure ? 'on' : 'off'));
    Future<Socket> futureSocket =
        secure ? SecureSocket.connect(host, port) : Socket.connect(host, port);
    await futureSocket.then((socket) {
      _engine = new ImapEngine(socket);
    });
  }
}
