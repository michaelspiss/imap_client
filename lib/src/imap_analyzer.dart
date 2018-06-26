part of ImapClient;

class ImapAnalyzer {

  /// The [ImapClient] instance that created this instance
  ImapClient _client;

  ImapAnalyzer(ImapClient client) {
    _client = client;
  }

  bool _skipAnalysis = false;

  Utf8Codec _utf8 = new Utf8Codec();

  int _literalLength = 0;
  int _stringLength = 0;
  int _literalId = -1; // -1 to make the map zero-indexed

  /// Remembers the last line inserted for the addition of literals
  String _lastLineType = '';

  /// Used for soon to be updated lines
  String _tempLine = '';

  /// Interprets server responses and calls specific handlers.
  ///
  /// Returns an [ImapResponse] via the completer, which contains command
  /// specific responses plus the command completion status (OK/BAD/NO).
  void interpretLines(List<String> responseLines, Completer completer) {
    // Identifies response types (status/size update/continue/tagged/untagged)
    // Groups:                          1      2          3             4        5              6       7       8                  9                    10      11       12             13
    RegExp identifier = new RegExp("^(?:((A[0-9]+|\\*) ([a-z]+)(?: \\[(.*?)(?: (.*))?\\])?(?: (.*?))?)|(\\* ([0-9]+) (EXISTS|RECENT|EXPUNGE|FETCH)(?: (.*?))?)|(\\+(?: (.*?))?))(?: {([0-9]+)})?\$",
      caseSensitive: false);
    Map<String, dynamic> results = ImapResponse.getResponseBlueprint();
    results['fullResponse'] = responseLines.join();
    for(int i = 0; i<responseLines.length; i++) {
      String line = responseLines[i];
      if(_skipAnalysis) {
        _stringLength += _utf8.encode(line).length;
        results['literals'][_literalId.toString()] += line;
        _skipAnalysis = _literalLength > _stringLength;
        continue;
      }
      Match match = identifier.firstMatch(line.trim());
      if(line.isEmpty || line == '\r' || _matchHasGroup(match, 11)) {
        // skip empty / "continue" - CR are not removed by trim -> extra check
        continue;
      }
      else if(_matchHasGroup(match, 1)) { // tagged/untagged response
        _commonResponseAnalyzer(match, results, (i+1 == responseLines.length));
      }
      else if(_matchHasGroup(match, 7)) { // msg status / mailbox size update
        _handleSizeStatusUpdate(match);
      }
      else {
        _appendToLast(results, line);
      }
      if(_matchHasGroup(match, 13)) { // command has literal
        _captureLiteral(int.parse(match.group(13)), results);
      }
    }
    completer.complete(ImapResponse.fromMap(results));
  }

  /// Helper method to analyze tagged and untagged responses
  void _commonResponseAnalyzer(Match match, Map results,
      bool isLastLine) {
    bool isTagged = match.group(2) != '*';
    String id = _getGroupValue(match, 3).toUpperCase();
    String type =   id == 'OK' ? 'notices' :
                    id == 'NO' ? 'warnings' :
                    id == 'BAD' ? 'errors' : '';
    if(type.isNotEmpty) {
      results[type].add(_getGroupValue(match, 6));
      _lastLineType = type;
    } else {
      results['untagged'].add(new MapEntry<String, String>(id,
          _getGroupValue(match, 6)));
      _lastLineType = 'untagged';
    }
    if(_matchHasGroup(match, 4)) {
      results['responseCodes'][_getGroupValue(match, 4).toUpperCase()] =
          _getGroupValue(match, 5);
    }
    if(isLastLine && isTagged) {
      results['status'] = id;
      results['statusInfo'] = _getGroupValue(match, 6);
    }
  }

  /// Calls handlers for message status / mailbox size updates
  ///
  /// Match from sizeStatusUpdate regexp in [interpretLines]
  void _handleSizeStatusUpdate(Match m) {
    switch(m.group(9).toUpperCase()) {
      case 'EXISTS':
        _client.existsHandler?.call(_client._selectedMailbox, m.group(8));
        break;
      case 'RECENT':
        _client.recentHandler?.call(_client._selectedMailbox, m.group(8));
        break;
      case 'EXPUNGE':
        _client.expungeHandler?.call(_client._selectedMailbox, m.group(8));
        break;
      case 'FETCH':
        if(_matchHasGroup(m, 13)) { // has literal

        } else {
          _client.fetchHandler?.call(
              _client._selectedMailbox, m.group(8), _getGroupValue(m, 10)
          );
        }
        break;
    }
  }

  /// Prepares the capturing of a new literal. Returns the new literal's id
  int _captureLiteral(int length, Map results) {
    _literalLength = length;
    _stringLength = 0;
    _literalId = ++_literalId;
    results['literals'][_literalId.toString()] = '';
    if(_literalLength > 0) {
      _skipAnalysis = true;
    }
    _appendToLast(results, ' {$_literalId}');

    return _literalId;
  }

  void _appendToLast(Map results, String string) {
    List list = results[_lastLineType];
    var last = list.last;
    if(last is MapEntry) {
      last = new MapEntry<String, String>(last.key, last.value + string);
    } else {
      last += string;
    }
    list.removeLast();
    list.add(last);
  }

  /// Helper method to get values from (possibly inexistent) [Match] groups
  String _getGroupValue(Match match, int group) {
    try {
      return match.group(group) ?? '';
    } catch(e) {
      return '';
    }
  }

  /// Helper method to determine whether a group exists in a [Match]
  bool _matchHasGroup(Match m, int group) {
    return _getGroupValue(m, group).isNotEmpty;
  }
}