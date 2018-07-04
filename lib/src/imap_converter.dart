part of ImapClient;

class ImapConverter {

  /// Converts a regular list to a parenthesized imap list
  static String dartListToImapList(List<String> list) {
    String listString = list.toString();
    return '(' +
        listString.substring(1, listString.length - 1).replaceAll(',', '') +
        ')';
  }

  /// Converts a Map into a parenthesized imap list of attribute/value pairs
  static String dartMapToImapList(Map<String, String> map) {
    List<String> list = <String>[];
    map.forEach((String key, String value) {
      list..add(key)..add(value);
    });
    return dartListToImapList(list);
  }

  /// Turns an imap list (one two three) into a dart list [one, two, three]
  static List<String> imapListToDartList(String string) {
    string = string.trim();
    Match match = new RegExp('^\\(? *(.*?) *\\)?\$').firstMatch(string);
    if (match == null) {
      return <String>[];
    }
    return match.group(1).split(" ")
      ..removeWhere((string) {
        return string.isEmpty;
      });
  }

  /// Turns a List (One Two Three Four) into a Map {One: Two, Three: Four}
  static Map<String, String> imapListToDartMap(String string) {
    List<String> parts = imapListToDartList(string);
    Map<String, String> map = <String, String>{};
    if(parts.isEmpty) {
      return map;
    }
    for (int i = 0; i < parts.length; i++) {
      map[parts[i]] = ++i < parts.length ? parts[i] : "";
    }
    return map;
  }
}