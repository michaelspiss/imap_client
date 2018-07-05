part of ImapClient;

/// Holds the logic for classifying lines and acting on them.
class _ImapAnalyzer {
  /// The [ImapClient] instance that created this instance
  ImapClient _client;

  /// Indicates that the line is in a literal and not supposed to be analyzed
  bool _skipAnalysis = false;

  /// Indicates that the incoming line as a greeting and needs special treatment
  bool _isGreeting = true;

  /// Holds all known command tags used by [ImapClient]
  List<String> _registeredTags = <String>[];

  /// Temporal storage for responses with literals
  String _tempLine = '';
  Match _tempMatch;
  List<String> _literals = [];
  String _literal = '';

  /// Literal character counter
  Utf8Codec _utf8 = new Utf8Codec();
  int _actualLiteralLength;
  int _currentLiteralLength;
  int _literalId = -1; // to make it 0 indexed.

  /// Controls [updates]
  StreamController _updates = new StreamController.broadcast();

  /// Sends command status updates back to the client
  ///
  /// {"tag": tag, "status": "continue", "info": "foo"} or
  /// {"tag": tag, "status": "complete", "response": [_ImapResponse]}
  Stream get updates => _updates.stream;

  /// Holds results of the current tag's analysis data
  Map<String, dynamic> _results = _ImapResponse.getResponseBlueprint();

  /// Splits an incoming response line into "semantic parts"
  // Groups:                         1                      2     3           4             5       6                     7         8       9                   10                    11             12          13                   14
  RegExp _splitter = new RegExp('^(\\s+\$)|^(?:[\\r\\n])?(?:((A[0-9]+|\\*) ([a-z]+)(?: \\[(.*?)(?: (.*))?\\])?(?: ([^{\\r\\n]+?))?)|(\\* ([0-9]+) (EXISTS|RECENT|EXPUNGE|FETCH)(?: ([^\\r\\n]+?))?)|(\\+(?: ([^{\\r\\n]+?)?)?))(?: {([0-9]+)})?\$',
      caseSensitive: false);

  /// [client] must be the instance the analyser was instantiated in
  _ImapAnalyzer(ImapClient client) {
    _client = client;
  }

  /// Registers a new tag used by the client.
  ///
  /// This is mainly needed for possible command continue requests where the
  /// tag is not known beforehand. Works FIFO, so the first tag will always be
  /// used for command continue request callbacks.
  void registerTag(String tag) {
    _registeredTags.add(tag);
  }

  /// Interprets server responses and calls specific handlers.
  ///
  /// Returns an [_ImapResponse] via the completer, which contains command
  /// specific responses plus the command completion status (OK/BAD/NO).
  void analyzeLine(String line) {
    if (_skipAnalysis) {
      line = _addLineToLiteral(line);
      if (line.isEmpty) {
        return;
      }
    }
    _handleLine(line);
  }

  /// Decides which type of response was sent and handles it accordingly
  void _handleLine(String line, [List<String> literals = null]) {
    Match match = _splitter.firstMatch(line);
    bool hasLiteral = _matchHasGroup(match, 14); // checks for tailing literal
    _results['fullResponse'] += line;
    String type = _getTypeFromMatch(match);
    if (hasLiteral) {
      _setTemp(line, match);
    } else if (type == 'empty') {
      // ignore
    } else if (type == 'continue') {
      _handleTemp();
      _handleContinue(_getGroupValue(match, 13) /* info */);
    } else if (type == 'standard') {
      _handleTemp();
      _handleStandardResponse(match);
    } else if (type == 'update') {
      _handleTemp();
      _handleSizeStatusUpdate(match);
    } else {
      _tempLine.isNotEmpty
          ? _addStringToTempLine(line)
          : _results['unrecognizedLines'].add(line);
    }
  }

  /// Sets a new temporal line
  void _setTemp(String line, Match match) {
    _addStringToTempLine(line);
    _tempMatch = match;
  }

  /// Handles a line that was in the temp. storage (has at least one literal)
  _handleTemp() {
    if (_tempLine.isEmpty) {
      return;
    }
    Match match = _splitter.firstMatch(_tempLine);
    String type = _getTypeFromMatch(match);
    if (type == 'continue') {
      _handleContinue(_literals.first); // literal only possible for info
    } else if (type == 'standard') {
      _handleStandardResponse(_tempMatch);
    } else if (type == 'update') {
      _handleSizeStatusUpdate(_tempMatch, true);
    }
    _tempLine = '';
    _tempMatch = null;
    _literalId = -1;
    _literal = '';
    _literals = <String>[];
  }

  /// Handler for a standard tagged / untagged response
  void _handleStandardResponse(Match match) {
    bool isTagged = match.group(3) != '*';
    String id = match.group(4).toUpperCase();
    String type = id == 'OK' ? 'notices'
                : id == 'NO' ? 'warnings'
                : id == 'BAD' ? 'errors' : '';
    if (type.isNotEmpty) {
      _results[type].add(_getGroupValue(match, 7)); // reason for ok/bad/no
    } else {
      _results['untagged'][id.toUpperCase()] = _getGroupValue(match, 7);
    }
    if (_matchHasGroup(match, 5)) {
      _results['responseCodes'][_getGroupValue(match, 5).toUpperCase()] =
          _getGroupValue(match, 6);
    }
    if (isTagged || _isGreeting) {
      _results['status'] = id;
      _results['statusInfo'] = _getGroupValue(match, 7);
      _updates.add({
        "tag": _isGreeting ? "connect" : match.group(3),
        "state": "complete",
        "response": _ImapResponse.fromMap(_results)
      });
      _registeredTags.remove(match.group(3));
      _results = _ImapResponse.getResponseBlueprint();
    }
    if (_isGreeting) {
      _isGreeting = false;
      _client._connectionState = id == 'PREAUTH' ? ImapClient.stateAuthenticated
                               : id == 'BYE' ? ImapClient.stateClosed
                               : ImapClient.stateConnected;
    }
  }

  /// Handles a command continuation request from the server
  _handleContinue(String info) {
    _updates
        .add({"tag": _registeredTags.first, "state": "continue", "info": info});
  }

  /// Calls handlers for message status / mailbox size updates
  ///
  /// Match from sizeStatusUpdate regexp [_splitter]
  void _handleSizeStatusUpdate(Match match, [bool useTemp = false]) {
    int messageNumber = int.parse(match.group(9));
    switch (match.group(10).toUpperCase()) {
      case 'EXISTS':
        _client.existsHandler?.call(_client._selectedMailbox, messageNumber);
        break;
      case 'RECENT':
        _client.recentHandler?.call(_client._selectedMailbox, messageNumber);
        break;
      case 'EXPUNGE':
        _client.expungeHandler?.call(_client._selectedMailbox, messageNumber);
        break;
      case 'FETCH':
        Map<String, String> attr = useTemp
            ? _getMapFromTemp()
            : ImapConverter.imapListToDartMap(_getGroupValue(match, 11));
        _client.fetchHandler
            ?.call(_client._selectedMailbox, messageNumber, attr);
        break;
    }
  }

  /// Creates a map {a: b, c: d} from an imap list (a b c d) in temp. storage.
  ///
  /// Handles literals.
  Map<String, String> _getMapFromTemp() {
    List<String> parts =
        new RegExp('\\((.*?)\\)').firstMatch(_tempLine).group(1).split(" ");
    parts.removeWhere((string) {
      return string.isEmpty;
    });
    Map<String, String> map = new Map<String, String>();
    for (int i = 0; i < parts.length; i++) {
      String value = ++i < parts.length ? parts[i] : "";
      Match match = new RegExp('{([0-9]+?)}').firstMatch(parts[i]);
      value = match != null ? _literals[int.parse(match.group(1))] : parts[i];
      map[parts[i - 1]] = value;
    }
    return map;
  }

  /// Returns the line's type from the [_splitter] match
  ///
  /// Possible types are: undefined, empty, standard, update and continue.
  /// empty: line is empty
  /// standard: tagged / untagged response
  /// update: command continuation request
  /// update: message status / mailbox size update
  /// undefined: line did not match any of the above
  String _getTypeFromMatch(Match match) {
    if (match == null) {
      return 'undefined'; // [_splitter] could not find a match
    }
    if (_matchHasGroup(match, 1)) {
      return 'empty'; // line is empty
    }
    if (_matchHasGroup(match, 2)) {
      return 'standard'; // tagged / untagged response
    }
    if (_matchHasGroup(match, 8)) {
      return 'update'; // message status / mailbox size update
    }
    if (_matchHasGroup(match, 12)) {
      return 'continue'; // command continuation request
    }
    return 'undefined'; // none of the above
  }

  /// Adds the line to a literal. Handles counting and cancels it automatically.
  ///
  /// Returns the end of the line if it is no longer part of the literal.
  String _addLineToLiteral(String line) {
    List<int> encoded = _utf8.encode(line);
    String rest = '';
    if (_currentLiteralLength + encoded.length > _actualLiteralLength) {
      int max = _currentLiteralLength + encoded.length - _actualLiteralLength;
      _literal += line.substring(0, max);
      rest = line.substring(max);
    } else {
      _currentLiteralLength += _utf8.encode(line).length;
      _literal += line;
    }
    _skipAnalysis = _currentLiteralLength < _actualLiteralLength;
    // if limit is reached
    if (!_skipAnalysis) {
      _literals.add(_literal);
      _literal = '';
    }
    return rest;
  }

  /// Adds a string that could not be classified to temp. Handles literals.
  void _addStringToTempLine(String string) {
    _tempLine +=
        string.trim().replaceFirstMapped(new RegExp('{([0-9]+?)}\$'), (match) {
              _captureLiteral(int.parse(match.group(1)));
              return '{$_literalId}';
            }) +
            " ";
  }

  /// Prepares the capturing of a new literal.
  void _captureLiteral(int length) {
    _actualLiteralLength = length;
    _currentLiteralLength = 0;
    _literal = '';
    _literalId++;
    if (_actualLiteralLength > 0) {
      _skipAnalysis = true;
    }
  }

  /// Helper method to get values from (possibly inexistent) [Match] groups
  String _getGroupValue(Match match, int group) {
    try {
      return match.group(group) ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Helper method to determine whether a group exists in a [Match]
  bool _matchHasGroup(Match m, int group) {
    return _getGroupValue(m, group).isNotEmpty;
  }
}
