part of imap_client;

/// Handles update responses like EXISTS, EXPUNGE, RECENT
typedef void UpdateHandler(String mailboxName, int messageNumber);
/// Handles fetch responses
typedef void FetchHandler(String mailboxName, int messageNumber,
    Map<String, String> attributes);
/// Handles messages sent by the server.
typedef void MessageHandler(String info);

/// The main class which acts as an interface for the imap 4 (rev 1) protocol
class ImapClient {
  ImapConnection _connection;

  /// Direct access to the connection. Might be needed for custom commands.
  ImapConnection get connection => _connection;

  _ImapAnalyzer _analyzer;

  // All possible connection states
  /// "There is no connection to a server"
  static const stateClosed = -1;

  /// There is a connection, but the client is not authenticated
  static const stateConnected = 0;

  /// Client is authenticated to the server
  static const stateAuthenticated = 1;

  /// The client is authenticated and has currently opened a mailbox
  static const stateSelected = 2;

  /// The client has opened a mailbox and is listening for changes
  static const stateIdle = 3;

  /// Increases every time a new tag is requested, see [requestNewTag]
  int _tagCounter = 0;

  /// Contains all supported authentication methods
  Map<String, Function> _authMethods = new Map();

  /// Holds all server capabilities. This is updated automatically.
  List<String> _serverCapabilities = <String>[];

  List<String> get serverCapabilities => _serverCapabilities;

  /// Holds the name of all authentication methods supported by the server
  List<String> _serverSupportedAuthMethods = <String>[];

  List<String> get serverSupportedAuthMethods => _serverSupportedAuthMethods;

  /// The current connection state
  int _connectionState = stateClosed;

  int get connectionState => _connectionState;

  /// Indicates that the command issued next should be sent with prepended "UID"
  bool _commandUseUid = false;

  /// Streams single lines to the analyzer
  StreamController<String> _lines;

  /// Name of the selected mailbox. This does NOT indicate the selected state!
  String _selectedMailbox = '';

  String get selectedMailbox => _selectedMailbox;

  /// True, if the selected mailbox is connected to with read-write permissions
  bool _mailboxIsReadWrite = false;

  bool get mailboxIsReadWrite => _mailboxIsReadWrite;

  // Handlers for specific (unsolicited) server responses.
  /// Handler for EXISTS update responses.
  UpdateHandler existsHandler;

  /// Handler for RECENT update responses.
  UpdateHandler recentHandler;

  /// Handler for EXPUNGE update responses.
  UpdateHandler expungeHandler;

  /// Handler for FETCH update responses.
  FetchHandler fetchHandler;

  /// Handles ALERT responses. Those should be shown to the user.
  MessageHandler alertHandler;

  ImapClient() {
    _connection = new ImapConnection();
    _analyzer = new _ImapAnalyzer(this);
    _lines = new StreamController<String>();
    _lines.stream.listen(_analyzer.analyzeLine);
    setAuthMethod("plain", _authPlain);
    setAuthMethod("login", _authLogin);
  }

  /// Splits blocks into single lines and passes them to the analyzer
  void _responseHandler(response) {
    response = new String.fromCharCodes(response);
    List<String> lines = response.split(new RegExp('(?=\r\n|\n|\r)'));
    _lines.addStream(Stream.fromIterable(lines));
  }

  /// Checks if an authentication method is supported. Capitalization is ignored
  bool clientSupportsAuth(String methodName) {
    return _authMethods.containsKey(methodName.toLowerCase());
  }

  /// Registers an authentication method handler. Capitalization is ignored.
  ///
  /// This method may overwrite existing handlers with the same name.
  void setAuthMethod(String methodName, Function handler) {
    _authMethods[methodName.toLowerCase()] = handler;
  }

  /// Returns if the server has a certain capability.
  ///
  /// It automatically gets the list if it isn't loaded yet. Using this method
  /// is more favorable than calling capability yourself.
  Future<bool> serverHasCapability(String name) async {
    if (_serverCapabilities.isEmpty) {
      await capability();
    }
    return _serverCapabilities.contains(name.toUpperCase());
  }

  /// Generates a new unique tag
  String requestNewTag() {
    return 'A' + (_tagCounter++).toString();
  }

  /*
  Inner methods
   */

  /// Prepares tag for a new command
  ///
  /// Use the optional [tag] to use a specific tag and don't create a new one.
  String _prepareTag([String tag]) {
    if (tag.isEmpty) {
      tag = requestNewTag();
    }
    _analyzer.registerTag(tag);
    return tag;
  }

  /// Prepares response state change listeners for a new command
  ///
  /// [tag] is the used tag to listen for, [onContinue] allows for callbacks
  /// whenever there is a command continuation request. Callbacks must take
  /// a string (additional info sent by the client) as parameter.
  /// Returns a [Future] that indicates command completion (tagged response).
  Future<_ImapResponse> _prepareResponseStateListener(String tag,
      [Function onContinue = null]) {
    var completer = new Completer<_ImapResponse>();
    StreamSubscription subscription;
    subscription = _analyzer.updates.listen((responseState) {
      if (responseState['tag'] == tag) {
        if (responseState['state'] == 'complete') {
          subscription.cancel();
          completer.complete(responseState['response']);
        } else if (responseState['state'] == 'continue') {
          onContinue?.call(responseState['info']);
        }
      }
    });
    return completer.future;
  }

  /// Handles all response codes that are meant for the client
  void _handleResponseCodes(Map<String, String> responseCodes) {
    responseCodes.forEach((String key, String value) {
      key = key.toUpperCase();
      if (key == 'CAPABILITY') {
        _codeCapability(value);
      } else if (key == 'ALERT') {
        alertHandler?.call(value);
      } else if (key == 'READ-WRITE') {
        _mailboxIsReadWrite = true;
      } else if (key == 'READ-ONLY') {
        _mailboxIsReadWrite = false;
      }
    });
  }

  /// Sends a [command] to the server.
  ///
  /// A new [tag] is being created automatically if not given. [tag] MUST be a
  /// new unique tag from [requestNewTag]. [onContinue] is being called every
  /// time there is a command continuation request (+) from the server. It
  /// returns a [Future], that indicates command completion and carries the
  /// responded block.
  Future<_ImapResponse> sendCommand(String command,
      [MessageHandler onContinue = null, String tag = '']) {
    tag = _prepareTag(tag);
    Future<_ImapResponse> completion =
        _prepareResponseStateListener(tag, onContinue);
    String uid = _commandUseUid ? "UID " : "";
    _commandUseUid = false;
    _connection.writeln('$tag $uid$command');
    completion.then((response) {
      _handleResponseCodes(response.responseCodes);
    });
    return completion;
  }

  /*
  Helper methods
   */

  /// Checks if the client is in the "connected" or a higher state
  bool isConnected() {
    return _connectionState >= 0;
  }

  /// Checks if the client is in the "authenticated" or a higher state
  bool isAuthenticated() {
    return _connectionState >= 1;
  }

  /// Checks if the client is in the "selected" state
  bool isSelected() {
    return _connectionState == 2;
  }

  /// Checks if the client is currently in the "idle" state - idle is running
  bool isIdle() {
    return _connectionState == 3;
  }

  /*
  Response code handlers
   */

  void _codeCapability(String capabilities) {
    _serverCapabilities = ImapConverter.imapListToDartList(capabilities);
    _serverSupportedAuthMethods.clear();
    _serverCapabilities.removeWhere((item) {
      if (item.startsWith(RegExp('AUTH=', caseSensitive: false))) {
        _serverSupportedAuthMethods.add(item.substring(5));
        return true;
      }
      return false;
    });
  }

  /*
   * COMMANDS
   */

  /// Connects to [host] in [port], uses SSL and TSL if [secure] is true
  ///
  /// It's highly recommended to (a)wait for this to finish.
  Future<_ImapResponse> connect(String host, int port, bool secure) {
    Future<_ImapResponse> completion = _prepareResponseStateListener('connect');
    _analyzer._isGreeting = true;
    _connection.connect(host, port, secure, _responseHandler, () {
      _connectionState = stateClosed;
      _selectedMailbox = '';
      _mailboxIsReadWrite = false;
      _commandUseUid = false;
      _serverCapabilities.clear();
      _serverSupportedAuthMethods.clear();
    });
    completion.then((response) {
      _handleResponseCodes(response.responseCodes);
    });
    return completion;
  }

  /// Imap command. Updates the capability and supported auth methods lists.
  ///
  /// This should only be used right after the connect and right after the
  /// authentication. It should not be used if it was already updated via
  /// a response code. Check the [_ImapResponse] of both [connect] and
  /// [authenticate]/[login] for already updated lists.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> capability() {
    return sendCommand('CAPABILITY')
      ..then((response) {
        if (response.untagged.containsKey('CAPABILITY')) {
          _codeCapability(response.untagged['CAPABILITY']);
        }
      });
  }

  /// Does nothing
  ///
  /// Can be used to prevent an automatic disconnect from the server due to
  /// inactivity and also to periodically fetch mailbox changes.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> noop() {
    return sendCommand('NOOP');
  }

  /// Ends the session, server closes connection
  ///
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> logout() {
    return sendCommand('LOGOUT')
      ..then((_) {
        _connectionState = stateClosed;
      });
  }

  /// Authenticates the user via the given authentication mechanism
  ///
  /// Throws an [UnsupportedError] if a by the client unsupported auth method
  /// is used.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> authenticate(String username, String password,
      [String authMethod = "plain"]) {
    authMethod = authMethod.toLowerCase();
    var bytes_username = utf8.encode(username);
    var bytes_password = utf8.encode(password);
    _IterationWrapper iteration = new _IterationWrapper();
    if (!clientSupportsAuth(authMethod)) {
      throw new UnsupportedError("Authentication method \"$authMethod\" is not "
          "supported by this client. Use setAuthMethod() to support it.");
    }
    return sendCommand('AUTHENTICATE $authMethod', (String info) {
      _authMethods[authMethod](
          _connection, bytes_username, bytes_password, iteration);
    })
      ..then((response) {
        if (response.isOK()) _connectionState = stateAuthenticated;
        if (!response.responseCodes.containsKey("CAPABILITY")) {
          _serverCapabilities.clear();
          _authMethods.clear();
        }
      });
  }

  /// Upgrades an insecure connection to a TLS encrypted one. DEPRECATED!
  ///
  /// Deprecated by RFC 8314, use a secure connection if possible.
  /// TLS negotiation is not part of this package. It begins right *after*
  /// command completion, no further commands must be issued while the
  /// negotiation is not complete. Returns the [ImapConnection] so a
  /// communication with the server is possible to implement.
  /// Again, this method should not be used anymore!
  /// Defined in RFC 3501 (Imap v4rev1)
  @deprecated
  ImapConnection starttls() {
    sendCommand('STARTTLS');
    return _connection;
  }

  /// Logs th user in via plaintext username and password
  ///
  /// This method can be forbidden by the server by having the LOGINDISABLED
  /// capability. If this method is still used, it will throw an
  /// [UnsupportedError].
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> login(String username, String password) {
    if (_serverCapabilities.contains("LOGINDISABLED")) {
      throw new UnsupportedError("LOGIN is forbidden by the server.");
    }
    return sendCommand('LOGIN "$username" "$password"')
      ..then((response) {
        if (response.isOK()) _connectionState = stateAuthenticated;
        if (!response.responseCodes.containsKey("CAPABILITY")) {
          _serverCapabilities.clear();
          _authMethods.clear();
        }
      });
  }

  /*
  Commands - Authenticated state only
   */

  /// Selects the mailbox with the given name
  ///
  /// On select, it first deselects the current mailbox. If the select fails,
  /// it stays in the unselected state. Please check the [mailboxIsReadWrite]
  /// attribute to see if the client is allowed to modify the mailbox.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> select(String mailbox) {
    _connectionState = stateAuthenticated;
    _selectedMailbox = '';
    _mailboxIsReadWrite = false;
    Future<_ImapResponse> future = sendCommand('SELECT "$mailbox"');
    future.then((_ImapResponse res) {
      if (res.isOK()) {
        _connectionState = stateSelected;
        _selectedMailbox = mailbox;
        _mailboxIsReadWrite = !res.responseCodes.containsKey('READ-ONLY');
      }
    });
    return future;
  }

  /// Does the same as [select], but the selected mailbox is read-only
  ///
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> examine(String mailbox) {
    return sendCommand('EXAMINE "$mailbox"');
  }

  /// Creates a new mailbox with the given name.
  ///
  /// OK on success, NO if something went wrong. To create a hierarchy, the
  /// name must include the hierarchy separator as returned by [list].
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> create(String mailbox) {
    return sendCommand('CREATE "$mailbox"');
  }

  /// Deletes the mailbox with the given name and all mails inside.
  ///
  /// This does not remove inferior mailboxes in their hierarchy.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> delete(String mailbox) {
    return sendCommand('DELETE "$mailbox"');
  }

  /// Renames a mailbox
  ///
  /// This does also rename inferior mailboxes if part of a hierarchy.
  /// (foo -> bar, foo/zap -> bar/zap). Renaming INBOX moves all messages
  /// inside to the new mailbox, leaving INBOX empty. If INBOX has inferiors,
  /// those are unaffected.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> rename(String mailbox, String newMailboxName) {
    return sendCommand('RENAME "$mailbox" "$newMailboxName"');
  }

  /// Adds a mailbox to the "active/subscribed" list as returned by [lsub]
  ///
  /// The server may check for its existence, but does not automatically remove
  /// it from this list should it be removed.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> subscribe(String mailbox) {
    return sendCommand('SUBSCRIBE "$mailbox"');
  }

  /// Removes a mailbox from the "active/subscribed" list as returned by [lsub]
  ///
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> unsubscribe(String mailbox) {
    return sendCommand('UNSUBSCRIBE "$mailbox"');
  }

  /// Returns a subset of mailbox names available to the client.
  ///
  /// An empty ("") [referenceName] indicates, that the returned names must be
  /// interpretable by [select]. The returned names must match the
  /// [mailboxName] pattern, which can contain wildcards (% and *).
  /// [referenceName] is a mailbox name or a level of mailbox hierarchy. An
  /// empty [mailboxName] returns the hierarchy delimiter or NIL if there is
  /// none. # is a breakout character if the server implements the namespace
  /// convention. Wildcards: * matches zero or more characters, whereas %
  /// matches all characters except th hierarchy delimiter.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> list(String referenceName, String mailboxName) {
    return sendCommand('LIST "$referenceName" "$mailboxName"');
  }

  /// Returns a subset of the "active/subscribed" list the same way as [list]
  ///
  /// The returned list may have different flags, in this case [list] is more
  /// trustworthy. If "foo/bar" is subscribed, but the % wildcard is used, foo
  /// is returned with the \Noselect attribute.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> lsub(String referenceName, String mailboxName) {
    return sendCommand('LSUB "$referenceName" "$mailboxName"');
  }

  /// Requests the status of a mailbox without changing the currently selected
  ///
  /// This also does not affect the state of any messages inside the mailbox.
  /// This is an alternative to a second connection and running [examine].
  /// Status may be slow and resource intensive and thus should not not be used
  /// on the currently selected mailbox.
  /// Status data items: MESSAGES, RECENT, UIDNEXT, UIDVALIDITY, UNSEEN
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> status(String mailbox, List<String> statusDataItems) {
    String dataItems = ImapConverter.dartListToImapList(statusDataItems);
    return sendCommand('STATUS "$mailbox" $dataItems');
  }

  /// Appends a message to the end of a mailbox with the given flags (+ \Recent)
  ///
  /// If the [dateTime] string is set, it will also be set in the new message.
  /// If the append is unsuccessful, the state before the attempt is restored.
  /// If the mailbox does not exist, an error is returned. If it could be
  /// created, a TRYCREATE response code is sent.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> append(String mailbox, String message,
      [String dateTime = "", List<String> flags]) {
    dateTime = dateTime.isEmpty ? "" : " " + dateTime;
    String flagsString =
        flags == null ? "" : " " + ImapConverter.dartListToImapList(flags);
    Utf8Encoder encoder = new Utf8Encoder();
    List<int> convertedMessage = encoder.convert(message);
    int length = convertedMessage.length;
    return sendCommand('APPEND "$mailbox"$flagsString$dateTime {$length}',
        (String info) {
      _connection.writeln(message);
    });
  }

  /*
  Commands - Selected state only
   */

  /// The same as [noop], may trigger housekeeping operations on the server side
  ///
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> check() {
    return sendCommand('CHECK');
  }

  /// Closes a mailbox and goes back to unselected state.
  ///
  /// Also removes all messages with the \Deleted flag in the selected mailbox.
  /// [select]/[examine] don't need a close when changing the mailbox.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> close() {
    Future<_ImapResponse> future = sendCommand('CLOSE');
    future.then((_ImapResponse res) {
      if (res.isOK()) {
        _connectionState = stateAuthenticated;
        _selectedMailbox = '';
        _mailboxIsReadWrite = false;
      }
    });
    return future;
  }

  /// Removes all messages that have the \Deleted flag in the selected mailbox.
  ///
  /// Responds with an untagged EXPUNGE for each deleted message with its
  /// relative id (position) -> EXPUNGE 3, EXPUNGE 3, EXPUNGE 4 will actually
  /// remove messages 3,4 and 6.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> expunge() {
    return sendCommand('EXPUNGE');
  }

  /// Returns a list of messages that match the [searchCriteria].
  ///
  /// [charset] can be used to define a specific encoding that should be used.
  /// If the charset is not supported, the response code BADCHARSET will be
  /// sent along with a NO response.
  /// Matching is case insensitive. Please look at the rfc for a full list of
  /// defined search keys.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> search(String searchCriteria, [String charset = ""]) {
    charset = charset.isEmpty ? "" : "CHARSET " + charset + " ";
    return sendCommand('SEARCH $charset$searchCriteria');
  }

  /// Returns message data to the client.
  ///
  /// Matching is case insensitive. Please look at the rfc for a full list of
  /// defined message data item names.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> fetch(String sequenceSet, List<String> dataItemNames) {
    String dataItems = ImapConverter.dartListToImapList(dataItemNames);
    return sendCommand('FETCH $sequenceSet $dataItems');
  }

  /// Alters data associated with a message
  ///
  /// Normally, the updated value is returned with an untagged fetch, but this
  /// can be disabled with .SILENT right after the item data name.
  /// Data item names:
  /// FLAGS <flag list> - replaces all flags other than \Recent
  /// +FLAGS <flag list> - adds flags
  /// -FLAGS <flag list> - removes flags
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> store(
      String sequenceSet, String dataItem, String dataValue) {
    return sendCommand('STORE $sequenceSet $dataItem $dataValue');
  }

  /// Copies the messages specified to another mailbox
  ///
  /// Flags and internaldate should be preserved, \Recent should be set.
  /// If the mailbox does not exist TRYCREATE is sent as response code along
  /// a NO response.
  /// Defined in RFC 3501 (Imap v4rev1)
  Future<_ImapResponse> copy(String sequenceSet, String mailbox) {
    return sendCommand('COPY $sequenceSet $mailbox');
  }

  /// Converts message sequence numbers to unique identifiers.
  ///
  /// Can be used with [copy], [fetch] or [store] -> sequence numbers are now
  /// unique identifiers ([fetch] still sends message sequence numbers, but with
  /// additional "UID"). [search] returns UIDs instead of sequence numbers, but
  /// command arguments do not change.
  /// Defined in RFC 3501 (Imap v4rev1)
  ImapClient uid() {
    _commandUseUid = true;
    return this;
  }

  /// Listens for changes to the currently selected mailbox
  ///
  /// To make the server aware that this client is still active and prevent a
  /// timeout, idle should be re-issued at least every 29 minutes.
  /// Throws an [UnsupportedError] if the server does not support the idle
  /// command.
  /// Defined in RFC 2177 (IMAP4 IDLE command)
  Future<_ImapResponse> idle(
      [Duration duration = const Duration(minutes: 29)]) async {
    if (!await serverHasCapability("IDLE")) {
      throw new UnsupportedError("Server does not support the idle command");
    }
    int oldState = _connectionState;
    new Timer(duration, endIdle);
    return sendCommand('IDLE', (String info) {
      _connectionState = stateIdle;
    })
      ..then((_) {
        _connectionState = oldState;
      });
  }

  /// Ends the IDLE command and lets it return to the previous state
  void endIdle() {
    if (_connectionState == stateIdle) {
      _connection.writeln('DONE');
    }
  }
}
