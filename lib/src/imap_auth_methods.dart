part of imap_client;

/// Implements the "plain" authentication mechanism
class ImapPlainAuth extends ImapSaslMechanism {
  String _username;
  String _password;

  ImapPlainAuth(this._username, this._password) : super("plain");

  @override
  String challenge(String response) {
    List<int> bytes = [0]
      ..addAll(_username.codeUnits)
      ..add(0)
      ..addAll(_password.codeUnits);
    _isAuthenticated = true;
    return base64.encode(bytes);
  }
}

/// Implements the "login" sasl mechanism (not the same as login command!)
class ImapLoginAuth extends ImapSaslMechanism {
  String _username;
  String _password;
  int _step = 1;

  ImapLoginAuth(this._username, this._password) : super("login");

  @override
  String challenge(String response) {
    if (_step == 1) {
      return base64.encode(_username.codeUnits);
    } else {
      _isAuthenticated = true;
      return base64.encode(_password.codeUnits);
    }
  }
}
