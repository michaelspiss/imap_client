part of imap_client;

class ImapEngine {
  /// The socket used for communication with the imap server
  Socket _socket;

  /// A buffer for the imap server's responses
  ImapBuffer _buffer;

  /// Counter which keeps tags unique
  int _tagCount = 0;

  /// The currently selected folder, null if no selection
  ImapFolder _currentFolder;

  /// Holds the instruction that is currently being executed
  ImapCommand _currentInstruction;

  /// Holds information about initial server greeting completion
  ImapGreeting _greeting;

  /// [ImapInstruction] queue
  Queue<ImapCommand> _queue = new Queue();

  /// Server capabilities
  List<String> _capabilities = new List();

  /// Authentication methods supported by the server
  List<String> _serverAuthCapabilities = new List();

  /// True if this client is authenticated
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;

  /// Handler for alert messages from the server - must be shown to the user
  void Function(String) alertHandler;

  /// Handles expunge (message deletion) responses
  void Function(int message) expungeHandler;

  ImapEngine(Socket _connection) {
    _buffer = new ImapBuffer();
    _greeting = new ImapGreeting(this);
    _queue.add(_greeting);
    _setSocket(_connection);
  }

  /// Sets a new socket, needed for initial setup and starttls upgrade
  void _setSocket(Socket socket) {
    _socket = socket;
    _socket.listen(
        (response) {
          _buffer.addAll(response);
          if (_debugging) _logger.info("S: " + String.fromCharCodes(response));
        },
        cancelOnError: true,
        onDone: () {
          _logger.info("Connection has been terminated by the server.");
          _socket.destroy();
        });
  }

  /// Takes data and sends it to the server as-is.
  void write(Object data) {
    _socket.write(data);
    if (_debugging) _logger.info("C: " + data.toString());
  }

  /// Takes data and sends it to the server with appended CRLF.
  void writeln(Object data) {
    _socket.write(data.toString() + "\r\n");
    if (_debugging) _logger.info("C: " + data.toString() + "\r\n");
  }

  /// Returns a new unique tag for another command
  String generateTag() {
    return "A" + (_tagCount++).toString();
  }

  /// Enqueues an [ImapCommand] for execution.
  void enqueueCommand(ImapCommand command) {
      _queue.add(command);
  }

  /// Executes commands in the queue until it reaches [command].
  Future<ImapTaggedResponse> executeCommand(ImapCommand command) async {
    if (_queue.isEmpty)
      throw new MissingCommandException(
          "Trying to execute, but command queue is empty.");

    ImapTaggedResponse response;
    do {
      _currentInstruction = _queue.removeFirst();
      if (_currentInstruction.folder != _currentFolder) {
        response = await _selectFolder(_currentInstruction.folder);
        if (response != ImapTaggedResponse.ok) return response;
        _currentInstruction = _queue.removeFirst();
      }
      await _currentInstruction._before?.call();
      if (_currentInstruction == command) {
        response = await _currentInstruction.run(_buffer);
        _currentInstruction = null;
        return response;
      }
      await _currentInstruction.run(_buffer);
    } while (_queue.isNotEmpty);
    _currentInstruction = null;

    throw new MissingCommandException(
        "Reached end of command queue, but could not find given command. " +
            command.toString());
  }

  /// Selects folder before executing other commands
  Future<ImapTaggedResponse> _selectFolder(ImapFolder folder) async {
    ImapFolder oldFolder = _currentFolder;
    _currentFolder = folder;
    ImapCommand select;
    if (folder == null)
      select = new ImapCommand(this, folder, "CLOSE");
    else if (folder.isReadWrite == false)
      select = new ImapCommand(this, folder, "EXAMINE " + folder.name);
    else
      select = new ImapCommand(this, folder, "SELECT " + folder.name);
    _queue.addFirst(_currentInstruction);
    _queue.addFirst(select);
    ImapTaggedResponse response = await executeCommand(select);
    if (response == ImapTaggedResponse.no)
      _currentFolder = null;
    else if (response == ImapTaggedResponse.bad) _currentFolder = oldFolder;
    return response;
  }

  /// Checks if server has capability, also returns false if no data is present!
  bool hasCapability(String capability) {
    return _capabilities.contains(capability);
  }

  /// Acts on untagged responses sent by the server
  ///
  /// Expects the untagged response start token (*) to already be read. Always
  /// reads the whole line.
  Future<void> handleUntaggedResponse() async {
    ImapWord word = await _buffer.readWord();
    String wordValue = word.value.toUpperCase();

    if (_currentInstruction._untaggedHandlers.containsKey(wordValue)) {
      await _currentInstruction._untaggedHandlers[wordValue](_buffer);
      return;
    }
    switch (wordValue) {
      case 'BYE':
        _debugLog("Received BYE, " +
            _queue.length.toString() +
            " commands still in queue.");
        await _processPossibleResponseCode();
        break;
      case 'OK':
      case 'BAD':
      case 'NO':
        await _processPossibleResponseCode();
        break;
      case 'CAPABILITY':
        await _processCapability();
        break;
      case 'FLAGS':
        await _readFlagsList(_currentFolder._flags);
        await _buffer.skipLine();
        break;
      case 'PREAUTH':
        _isAuthenticated = true;
        await _processPossibleResponseCode();
        break;
      default:
        int number = int.tryParse(word.value);
        if (number == null) {
          await _processMissingHandler(lastWord: word.value);
          return;
        }
        // word is number
        word = await _buffer.readWord();
        wordValue = word.value.toUpperCase();
        if (_currentInstruction._untaggedHandlers.containsKey(wordValue)) {
          await _currentInstruction._untaggedHandlers[wordValue](_buffer,
              number: number);
          return;
        }
        switch (wordValue) {
          case 'EXISTS':
            _currentFolder._mailCount = number;
            await _buffer.skipLine();
            break;
          case 'RECENT':
            _currentFolder._recentCount = number;
            await _buffer.skipLine();
            break;
          case 'EXPUNGE':
            expungeHandler?.call(number);
            await _buffer.skipLine();
            break;
          default:
            // no handlers available, skip line
            await _processMissingHandler(lastWord: word.value);
        }
    }
  }

  Future<void> _processPossibleResponseCode() async {
    ImapWord word = await _buffer.readWord();
    if (word.type == ImapWordType.bracketOpen) await handleResponseCode();
    await _buffer.skipLine();
  }

  /// Handles response codes in [ ]. Must never read the newline char (\n)!
  Future<void> handleResponseCode() async {
    ImapWord word = await _buffer.readWord();
    String wordValue = word.value.toUpperCase();

    switch (wordValue) {
      case 'ALERT':
        await _skipUntilResponseCodeEnd();
        String message = await _buffer.readLine();
        if (_debugging) _logger.info('ALERT: ' + message);
        alertHandler?.call(message);
        _buffer.unread("\n");
        break;
      case 'CAPABILITY':
        await _processCapability();
        break;
      case 'PERMANENTFLAGS':
        await _readFlagsList(_currentFolder._permanentFlags);
        break;
      case 'READ-ONLY':
        _currentFolder._isReadWrite = false;
        break;
      case 'READ-WRITE':
        _currentFolder._isReadWrite = true;
        break;
      case 'UIDNEXT':
        int number = await _buffer.readInteger();
        _currentFolder._uidnext = number;
        break;
      case 'UIDVALIDITY':
        int number = await _buffer.readInteger();
        _currentFolder._uidvalidity = number;
        break;
      default:
        _currentInstruction._responseCode = wordValue;
    }
  }

  /// Skips (or logs if debugging enabled) line if there is no handler available
  Future<void> _processMissingHandler({String lastWord = ""}) async {
    if (_debugging) {
      _logger.info('Skipping untagged response, no handler available: ' +
          lastWord +
          " " +
          await _buffer.readLine());
      return;
    }
    await _buffer.skipLine();
  }

  /// Skips until the end of the current response code
  Future<void> _skipUntilResponseCodeEnd() async {
    ImapWord word = await _buffer.readWord();
    while (word.type != ImapWordType.bracketClose) {
      word = await _buffer.readWord();
    }
  }

  /// Updates [_capabilities] and [_serverAuthCapabilities] lists
  ///
  /// Expects "CAPABILITY" to already been read
  Future<void> _processCapability() async {
    _capabilities.clear();
    _serverAuthCapabilities.clear();
    ImapWord word = await _buffer.readWord();
    while (word.type != ImapWordType.bracketClose &&
        word.type != ImapWordType.eol) {
      String wordValue = word.value.toUpperCase();
      if (wordValue.length >= 5 && wordValue.substring(0, 5) == "AUTH=") {
        _serverAuthCapabilities.add(wordValue.substring(5));
      } else {
        _capabilities.add(wordValue);
      }
      word = await _buffer.readWord();
    }
  }

  /// Reads list of flags, expects list to start with "(" and end with ")"
  Future<void> _readFlagsList(List<String> target) async {
    ImapWord word = await _buffer.readWord(expected: ImapWordType.parenOpen);
    word = await _buffer.readWord();
    while (word.type != ImapWordType.parenClose) {
      target.add(word.value);
      word = await _buffer.readWord();
    }
  }
}
