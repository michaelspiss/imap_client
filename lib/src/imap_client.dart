part of imap_client;

/// Main point for interaction with the server
///
/// Handles commands that are not folder ("mailbox") specific and selects
class ImapClient extends _ImapCommandable {
  /// Host address the server is connected to
  String _host;

  String get host => _host;

  /// Port the server is connected to
  int _port;

  int get port => _port;

  /// If true, the communication with the server is encrypted
  bool _secure;

  bool get secure => _secure;

  /// Handler for alert messages from the server - must be shown to the user
  set alertHandler(Function(String) handler) => _engine.alertHandler = handler;

  /// Handler for expunge (message deletion) responses
  set expungeHandler(Function(int) handler) => _engine.expungeHandler = handler;

  /// Connects to the actual server
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
    await futureSocket.then((socket) async {
      _engine = new ImapEngine(socket);
      await _engine.executeCommand(_engine._greeting);
    });
  }

  /// Sends "LOGIN" command defined in rfc 3501
  ///
  /// Automatically sets the authenticated state.
  Future<ImapTaggedResponse> login(String username, String password) async {
    ImapTaggedResponse response = await sendCommand(
        "LOGIN \"$username\" \"$password\"", before: () async {
      _requiresNotAuthenticated("LOGIN");
      if (await _engine.hasCapability("LOGINDISABLED")) {
        _debugLog("Using LOGIN is forbidden by server");
        return ImapTaggedResponse.bad;
      }
    });
    if (response == ImapTaggedResponse.ok) {
      _engine._isAuthenticated = true;
      _engine._capabilities.clear();
    }
    return response;
  }

  /// Authenticates the client via the given [mechanism]
  ///
  /// Sends "AUTHENTICATE" command, defined in rfc 3501
  Future<ImapTaggedResponse> authenticate(ImapSaslMechanism mechanism) async {
    String mechanismName = mechanism.name.toUpperCase();
    ImapTaggedResponse response =
        await sendCommand("AUTHENTICATE " + mechanismName, before: () async {
      _requiresNotAuthenticated("AUTHENTICATE");
      await _engine.hasCapability(""); // update capabilities
      if (!_engine._serverAuthCapabilities.contains(mechanismName)) {
        _debugLog("AUTHENTICATE called with unsupported sasl mechanism \"" +
            mechanism.name +
            "\"");
        return ImapTaggedResponse.bad;
      }
    }, onContinue: (String response) {
      if (mechanism.isAuthenticated) {
        // something went wrong
        return ""; // escape from continue
      } else {
        return mechanism.challenge(response);
      }
    });
    if (mechanism.isAuthenticated && response == ImapTaggedResponse.ok) {
      _engine._isAuthenticated = true;
      _engine._capabilities.clear();
    }
    return response;
  }

  /// Sends "STARTTLS" command defined in rfc 3501
  ///
  /// Elevates unencrypted connection to be TLS encrypted.
  Future<ImapTaggedResponse> starttls() async {
    ImapTaggedResponse response =
        await sendCommand("STARTTLS", before: () async {
      _requiresNotAuthenticated("STARTTLS");
      if (_secure) {
        _debugLog("starttls command used, but connection is already secure.");
        return ImapTaggedResponse.bad;
      }
      if (!(await _engine.hasCapability("STARTTLS"))) {
        _debugLog(
            "STARTTLS is not enabled. Maybe you have to do a capability " +
                "request first.");
        return ImapTaggedResponse.bad;
      }
    });
    // Negotiate tls
    _engine._setSocket(await SecureSocket.secure(_engine._socket));
    return response;
  }

  /// Makes sure client is not authenticated, Throws [StateException] otherwise
  void _requiresNotAuthenticated(String command) {
    if (_engine.isAuthenticated)
      throw new StateException(
          "Trying to use \"" + command + "\" in authenticated state.");
  }
}
