part of ImapClient;

class ImapClient {

  ImapConnection _connection;

  /// Saves all responses in blocks defined by tags
  Map<String, List<String>> _responseBlocks = new Map();

  /// Tags used for commands that are awaiting a response
  List<String> _registeredTags = new List();

  /// Increases every time a new tag is requested, see [requestNewTag]
  int _tagCounter = 0;

  /// [Stream]s all tagged responses to let functions know their status changed
  ///
  /// Statuses are "complete" and "continue", new MapEntry(tag, status)
  StreamController<MapEntry<String, String>> _responseStates;

  /// Contains all supported authentication methods
  Map<String, Function> _authMethods = new Map();

  /// The matcher looking for tagged responses.
  // TODO: It's currently possible that this matches something in a message's body. The current workaround is appending a timestamp to the tag.
  RegExp _tagMatcher = new RegExp("^(A[0-9]+)\\s(BAD|NO|OK)", multiLine: true);

  /// The matcher looking for "continue" (+) responses.
  RegExp _continueMatcher = new RegExp("^\\+", multiLine: true);

  ImapClient() {
    _connection = new ImapConnection();
    _responseStates = new StreamController.broadcast();
    setAuthMethod("plain", _authPlain);
    setAuthMethod("login", _authLogin);
  }

  /// Connects to [host] in [port], uses SSL and TSL if [secure] is true
  ///
  /// It's highly recommended to (a)wait for this to finish.
  Future connect(String host, int port, bool secure) {
    var completer = new Completer();
    _connection.connect(host, port, secure, _responseHandler).then((_) {
      completer.complete();
    });
    return completer.future;
  }

  void _responseHandler(response) {
    response = new String.fromCharCodes(response);
    _responseBlocks[_registeredTags.first].add(response);
    // Marks corresponding tag as complete if the response is tagged
    Match match = _tagMatcher.firstMatch(response);
    if(match != null && match.group(1) == _registeredTags.first) {
      String tag = match.group(1);
      _registeredTags.removeAt(0); // remove from active tags
      _responseStates.add(new MapEntry(tag, 'complete'));
    }
    else if (_continueMatcher.firstMatch(response) != null) {
      String tag = _registeredTags.first;
      _responseStates.add(new MapEntry(tag, 'continue'));
    }
  }

  /// Checks if an authentication method is supported. Capitalization is ignored
  bool supportsAuth(String methodName) {
    return _authMethods.containsKey(methodName.toLowerCase());
  }

  /// Registers an authentication method handler. Capitalization is ignored.
  ///
  /// This method may overwrite existing handlers with the same name.
  void setAuthMethod(String methodName, Function handler) {
    _authMethods[methodName.toLowerCase()] = handler;
  }

  /// Generates a new unique tag
  String requestNewTag() {
    // workaround for regexp TODO
    int timestamp = new DateTime.now().millisecondsSinceEpoch;
    return 'A' + (_tagCounter++).toString() + timestamp.toString();
  }

  /// Prepares tag for a new command
  ///
  /// Use the optional [tag] to use a specific tag and don't create a new one.
  String _prepareTag([String tag]) {
    if(tag.isEmpty) {
    tag = requestNewTag();
    }
    _registeredTags.add(tag);
    _responseBlocks[tag] = new List();
    return tag;
  }

  /// Prepares response state change listeners for a new command
  ///
  /// [tag] is the used tag to listen for, [onContinue] allows for callbacks
  /// whenever there is a command continuation request.
  Completer _prepareResponseStateListener(String tag, Function onContinue) {
    var completer = new Completer();
    StreamSubscription subscription;
    subscription = _responseStates.stream.listen((responseState) {
      if(responseState.key == tag) {
        if(responseState.value == 'complete') {
          subscription.cancel();
          completer.complete(_responseBlocks[tag]);
          _responseBlocks.remove(tag);
        }
        else if (responseState.value == 'continue') {
          onContinue();
        }
      }
    });
    return completer;
  }

  /// Sends a [command] to the server.
  ///
  /// A new [tag] is being created automatically if not given. [tag] MUST be a
  /// new unique tag from [requestNewTag]. [onContinue] is being called every
  /// time there is a command continuation request (+) from the server. It
  /// returns a [Future], that indicates command completion and carries the
  /// responded block.
  Future sendCommand(String command, [Function onContinue = null,
    String tag = '']) {

    tag = _prepareTag(tag);
    var completer = _prepareResponseStateListener(tag, onContinue);
    _connection.writeln('$tag $command');
    return completer.future;
  }

  /*
   * COMMANDS
   */

  /// Sends the CAPABILITY command as defined in RFC 3501
  Future<List<String>> capability() {
    return sendCommand('CAPABILITY');
  }

  /// Sends the NOOP command as defined in RFC 3501
  Future<List<String>> noop() {
    return sendCommand('NOOP');
  }

  /// Sends the LOGOUT command as defined in RFC 3501
  Future<List<String>> logout() {
    return sendCommand('LOGOUT');
  }

  /// Sends the AUTHENTICATE command as defined in RFC 3501
  Future<List<String>> authenticate(String username, String password,
      [String authMethod = "plain"]) {
    authMethod = authMethod.toLowerCase();
    var bytes_username = utf8.encode(username);
    var bytes_password = utf8.encode(password);
    IterationWrapper iteration = new IterationWrapper();

    if(!supportsAuth(authMethod)) {
      return null; // TODO: Return error response/throw exception?
    }

    return sendCommand('AUTHENTICATE $authMethod', () {
      _authMethods[authMethod](
          _connection, bytes_username, bytes_password, iteration);
    });
  }

  /// Sends the AUTHENTICATE command as defined in RFC 3501
  ///
  /// Deprecated by RFC 8314, use a secure connection if possible.
  /// TLS negotiation is not part of this package. It begins *after* command
  /// completion, no further commands must be issued while the negotiation is
  /// not complete. Returns the [ImapConnection] so a communication with the
  /// server is possible to implement.
  /// Again, this method should not be used anymore!
  @deprecated
  ImapConnection starttls() {
    sendCommand('STARTTLS');
    return _connection;
  }
}
