part of ImapClient;

class ImapAnalyzer {

  /// The [ImapClient] instance that created this instance
  ImapClient _client;

  ImapAnalyzer(ImapClient client) {
    _client = client;
  }

  /// The results blueprint, later converted to an [ImapResponse]
  Map resultsBlueprint = {
    'status': '',
    'responseCodes': {},
    'untagged': [],
    'unrecognizedLines': [],
    'fullResponse': [],
    'notices': [],
    'warnings': [],
    'errors': []
  };

  /// Interprets server responses and calls specific handlers.
  ///
  /// Returns an [ImapResponse] via the completer, which contains command
  /// specific responses plus the command completion status (OK/BAD/NO).
  void interpretLines(List<String> responseLines, Completer completer) {
    // Identifies response types (status/size update/continue/tagged/untagged)
    // Groups:                       1       2         3             4        5              6     7       8                  9                    10     11       12
    RegExp identifier = new RegExp("^((A[0-9]+|\\*) ([a-z]+)(?: \\[(.*?)(?: (.*))?\\])?(?: (.*))?)|(\\* ([0-9]+) (EXISTS|RECENT|EXPUNGE|FETCH)(?: (.*))?)|(\\+(?: (.*))?)\$",
      caseSensitive: false);
    Map results = new Map.from(resultsBlueprint);
    results['fullResponse'] = responseLines.join('\n');
    for(int i = 0; i<responseLines.length; i++) {
      String line = responseLines[i];
      Match match = identifier.firstMatch(line);
      if(line.isEmpty || _matchHasGroup(match, 11)) { // empty / "continue"
        continue;
      }
      if(_matchHasGroup(match, 1)) { // tagged/untagged response
        _commonResponseAnalyzer(match, results, (i+1 == responseLines.length));
        continue;
      }
      if(_matchHasGroup(match, 7)) { // message status / mailbox size update
        _handleSizeStatusUpdate(match);
        continue;
      }
      results['unrecognizedLines'].add(line);
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
    } else {
      results['untagged'].add(new MapEntry(id, _getGroupValue(match, 6)));
    }
    if(_matchHasGroup(match, 4)) {
      results['responseCodes'][_getGroupValue(match, 4).toUpperCase()] =
          _getGroupValue(match, 5);
    }
    if(isLastLine && !isTagged) {
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
        _client.fetchHandler?.call(
            _client._selectedMailbox, m.group(8), m.group(10)
        );
        break;
    }
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