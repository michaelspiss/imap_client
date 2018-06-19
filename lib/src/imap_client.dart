part of ImapClient;

class ImapClient {

  ImapConnection _connection;

  /// All possible connection states
  static const stateClosed = -1;
  static const stateConnected = 0;
  static const stateAuthenticated = 1;
  static const stateSelected = 2;
  static const stateIdle = 3;

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

  /// The current connection state
  int _connectionState = stateClosed;
  int get connectionState => _connectionState;

  /// Indicates that the response is the initial greeting
  bool _isResponseGreeting = true;

  /// Indicates that the command issued next should be sent with prepended "UID"
  bool _commandUseUid = false;

  /// The matcher looking for tagged responses.
  RegExp _tagMatcher = new RegExp("^(A[0-9]+) (BAD|NO|OK)(?: (.*))?\$",
      caseSensitive: false, multiLine: true);

  /// The matcher looking for "continue" (+) responses.
  RegExp _continueMatcher = new RegExp("^\\+(?: (.*))?\$",
      multiLine: true);

  /// Name of the selected mailbox. This does NOT indicate the selected state!
  String _selectedMailbox = '';
  String get selectedMailbox => _selectedMailbox;

  /// Handlers for specific (unsolicited) server responses.
  Function existsHandler;
  Function recentHandler;
  Function expungeHandler;
  Function fetchHandler;

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
    _isResponseGreeting = true;
    _connection.connect(host, port, secure, _responseHandler, () {
      _connectionState = stateClosed;
      _selectedMailbox = '';
    }).then((_) {
      completer.complete();
    });
    return completer.future;
  }

  void _responseHandler(response) {
    response = new String.fromCharCodes(response);
    if(_isResponseGreeting) {
      _handleGreeting(response);
    } else {
      _handleServerResponse(response);
    }
  }

  void _handleGreeting(String response) {
    RegExp matcher = new RegExp('^\\* (BYE|OK|PREAUTH)', caseSensitive: false);
    Match match = matcher.firstMatch(response);
    if(match != null) {
      switch(match.group(1).toUpperCase()) {
        case 'OK':
          _connectionState = stateConnected;
          break;
        case 'PREAUTH':
          _connectionState = stateAuthenticated;
          break;
      }
      _isResponseGreeting = false;
    }
  }

  void _handleServerResponse(String response) {
    List<String> lines = response.split(new RegExp('\n|\r'));
    lines..removeLast()..removeLast(); // Remove CRLF at the end
    _responseBlocks[_registeredTags.first].addAll(lines);
    // Marks corresponding tag as complete if the response is tagged
    Match match = _tagMatcher.firstMatch(lines.last);
    if(match != null && match.group(1) == _registeredTags.first) {
      String tag = match.group(1);
      _registeredTags.removeAt(0); // remove from active tags
      _responseStates.add(new MapEntry(tag, 'complete'));
    }
    else if (_continueMatcher.firstMatch(lines.last) != null) {
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
    return 'A' + (_tagCounter++).toString();
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
  /// whenever there is a command continuation request. Returns a [Future] that
  /// indicates command completion (tagged response).
  Future _prepareResponseStateListener(String tag, Function onContinue) {
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
    return completer.future;
  }

  /// Calls handlers for message status / mailbox size updates
  void _handleSizeStatusUpdate(Match m) {
    switch(m.group(2).toUpperCase()) {
      case 'EXISTS':
        existsHandler?.call(_selectedMailbox, m.group(1));
        break;
      case 'RECENT':
        recentHandler?.call(_selectedMailbox, m.group(1));
        break;
      case 'EXPUNGE':
        expungeHandler?.call(_selectedMailbox, m.group(1));
        break;
      case 'FETCH':
        fetchHandler?.call(_selectedMailbox, m.group(1), m.group(3));
        break;
    }
  }

  /// Interprets server responses and calls specific handlers.
  ///
  /// Returns an [ImapResponse] via the completer, which contains command
  /// specific responses plus the command completion status (OK/BAD/NO).
  void _interpretResponse(List<String> responseLines, Completer completer) {
    RegExp tag = new RegExp('^A[0-9]+ (OK|NO|BAD)(?: .*)\$',
        caseSensitive: false);
    RegExp sizeStatusUpdate = new RegExp(
        '^\\* ([0-9]+) (EXISTS|RECENT|EXPUNGE|FETCH) ?(\\(.*\\))?\$',
        caseSensitive: false);
    String status = '';
    List<String> fullResponse = [];
    for(String line in responseLines) {
      if(line.isEmpty || _continueMatcher.firstMatch(line) != null) {
        continue;
      }
      Match m = tag.firstMatch(line);
      if(m != null && identical(line, responseLines.last)) {
        status = m.group(1);
        continue;
      }
      m = sizeStatusUpdate.firstMatch(line);
      if(m != null) {
        _handleSizeStatusUpdate(m);
        continue;
      }
      fullResponse.add(line);
    }
    completer.complete(new ImapResponse(status: status,
        response: fullResponse));
  }

  /// Sends a [command] to the server.
  ///
  /// A new [tag] is being created automatically if not given. [tag] MUST be a
  /// new unique tag from [requestNewTag]. [onContinue] is being called every
  /// time there is a command continuation request (+) from the server. It
  /// returns a [Future], that indicates command completion and carries the
  /// responded block.
  Future<ImapResponse> sendCommand(String command, [Function onContinue = null,
    String tag = '']) {

    tag = _prepareTag(tag);
    Future<List<String>> completion = _prepareResponseStateListener(tag,
        onContinue);
    String uid = _commandUseUid ? "UID " : "";
    _commandUseUid = false;
    _connection.writeln('$tag $uid$command');
    Completer interpretationCompleter = new Completer();
    completion.then((responseLines) {
      _interpretResponse(responseLines, interpretationCompleter);
    });
    return interpretationCompleter.future;
  }

  /*
  Helper methods
   */

  bool isConnected() {
    return _connectionState >= 0;
  }

  bool isAuthenticated() {
    return _connectionState >= 1;
  }

  bool isSelected() {
    return _connectionState == 2;
  }

  bool isIdle() {
    return _connectionState == 3;
  }

  /// Converts a regular list to an imap list string
  String _listToImapString(List<String> list) {
    String listString = list.toString();
    return '(' + listString.substring(1, listString.length-1)
        .replaceAll(',', '') + ')';
  }

  /*
   * COMMANDS
   */

  /// Sends the CAPABILITY command as defined in RFC 3501
  Future<ImapResponse> capability() {
    return sendCommand('CAPABILITY');
  }

  /// Sends the NOOP command as defined in RFC 3501
  Future<ImapResponse> noop() {
    return sendCommand('NOOP');
  }

  /// Sends the LOGOUT command as defined in RFC 3501
  Future<ImapResponse> logout() {
    _connectionState = stateClosed;
    return sendCommand('LOGOUT');
  }

  /// Sends the AUTHENTICATE command as defined in RFC 3501
  Future<ImapResponse> authenticate(String username, String password,
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

  /// Sends the LOGIN command as defined in RFC 3501
  Future<ImapResponse> login(String username, String password) {
    return sendCommand('LOGIN "$username" "$password"');
  }

  /*
  Commands - Authenticated state only
   */

  /// Sends the SELECT command as defined in RFC 3501
  Future<ImapResponse> select(String mailbox) {
    _connectionState = stateAuthenticated;
    _selectedMailbox = '';
    Future<ImapResponse> future = sendCommand('SELECT "$mailbox"');
    future.then((ImapResponse res) {
      if(res.isOK()) {
        _connectionState = stateSelected;
        _selectedMailbox =  mailbox;
      }
    });
    return future;
  }

  /// Sends the EXAMINE command as defined in RFC 3501
  Future<ImapResponse> examine(String mailbox) {
    return sendCommand('EXAMINE "$mailbox"');
  }

  /// Sends the CREATE command as defined in RFC 3501
  Future<ImapResponse> create(String mailbox) {
    return sendCommand('CREATE "$mailbox"');
  }

  /// Sends the DELETE command as defined in RFC 3501
  Future<ImapResponse> delete(String mailbox) {
    return sendCommand('DELETE "$mailbox"');
  }

  /// Sends the RENAME command as defined in RFC 3501
  Future<ImapResponse> rename(String mailbox, String newMailboxName) {
    return sendCommand('RENAME "$mailbox" "$newMailboxName"');
  }

  /// Sends the SUBSCRIBE command as defined in RFC 3501
  Future<ImapResponse> subscribe(String mailbox) {
    return sendCommand('SUBSCRIBE "$mailbox"');
  }

  /// Sends the UNSUBSCRIBE command as defined in RFC 3501
  Future<ImapResponse> unsubscribe(String mailbox) {
    return sendCommand('UNSUBSCRIBE "$mailbox"');
  }

  /// Sends the LIST command as defined in RFC 3501
  Future<ImapResponse> list(String referenceName, String mailboxName) {
    return sendCommand('LIST "$referenceName" "$mailboxName"');
  }

  /// Sends the LSUB command as defined in RFC 3501
  Future<ImapResponse> lsub(String referenceName, String mailboxName) {
    return sendCommand('LSUB "$referenceName" "$mailboxName"');
  }

  /// Sends the STATUS command as defined in RFC 3501
  Future<ImapResponse> status(String mailbox, List<String> statusDataItems) {
    String dataItems = _listToImapString(statusDataItems);
    return sendCommand('STATUS "$mailbox" $dataItems');
  }

  /// Sends the APPEND command as defined in RFC 3501
  Future<ImapResponse> append(String mailbox, String message,
      [String dateTime = "", List<String> flags]) {
    dateTime = dateTime.isEmpty ? "" : " " + dateTime;
    String flagsString = flags == null ? "" : " " + _listToImapString(flags);
    Utf8Encoder encoder = new Utf8Encoder();
    List<int> convertedMessage = encoder.convert(message);
    int length = convertedMessage.length;
    return sendCommand('APPEND "$mailbox"$flagsString$dateTime {$length}', () {
      _connection.writeln(message);
    });
  }

  /*
  Commands - Selected state only
   */

  /// Sends the CHECK command as defined in RFC 3501
  Future<ImapResponse> check() {
    return sendCommand('CHECK');
  }

  /// Sends the CLOSE command as defined in RFC 3501
  Future<ImapResponse> close() {
    Future<ImapResponse> future = sendCommand('CLOSE');
    future.then((ImapResponse res) {
      if(res.isOK()) {
        _connectionState = stateAuthenticated;
        _selectedMailbox = '';
      }
    });
    return future;
  }

  /// Sends the EXPUNGE command as defined in RFC 3501
  Future<ImapResponse> expunge() {
    return sendCommand('EXPUNGE');
  }

  /// Sends the SEARCH command as defined in RFC 3501
  Future<ImapResponse> search(String searchCriteria, [String charset = ""]) {
    charset = charset.isEmpty ? "" : "CHARSET " + charset + " ";
    return sendCommand('SEARCH $charset$searchCriteria');
  }

  /// Sends the FETCH command as defined in RFC 3501
  Future<ImapResponse> fetch(String sequenceSet, List<String> dataItemNames) {
    String dataItems = _listToImapString(dataItemNames);
    return sendCommand('FETCH $sequenceSet $dataItems');
  }

  /// Sends the STORE command as defined in RFC 3501
  Future<ImapResponse> store(String sequenceSet, String dataItem,
      String dataValue) {
    return sendCommand('STORE $sequenceSet $dataItem $dataValue');
  }

  /// Sends the COPY command as defined in RFC 3501
  Future<ImapResponse> copy(String sequenceSet, String mailbox) {
    return sendCommand('COPY $sequenceSet $mailbox');
  }

  /// Sends next command with prepended "UID"
  ImapClient uid() {
    _commandUseUid = true;
    return this;
  }

  /// Sends the IDLE command as defined in RFC 2177
  Future<ImapResponse> idle() {
    int oldState = _connectionState;
    return sendCommand('IDLE', () {
      _connectionState == stateIdle;
    }).then((_) {
      _connectionState == oldState;
    });
  }

  /// Ends IDLE session
  void endIdle() {
    if(_connectionState == stateIdle) {
      _connection.writeln('DONE');
    }
  }
}
