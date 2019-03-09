part of imap_client;

/// Classes extending this can be used as authentication mechanisms
abstract class ImapSaslMechanism {
  /// The mechanism's id
  final String name;

  /// Internal - optimal - state, does not necessarily represent actual state
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;

  /// [name] is this mechanism's id, will be matched with server's capabilities
  ///
  /// If this id is not part of the server's accepted auth mechanisms, an
  /// error will be thrown at runtime. [name] is not case-sensitive.
  ImapSaslMechanism(this.name);

  /// Crafts answer to server's response
  ///
  /// Return value is a string that will be sent to the server, with appended
  /// CRLF (newline). Do not use CRLF (\r\n) in this response.
  String challenge(String response);
}
