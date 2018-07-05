part of ImapClient;

/// A class containing static methods to convert between imap and dart list/map
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
  ///
  /// Throws an [ArgumentError] if the string is not a valid imap list.
  /// Valid lists are: List with parenthesis: " (one two three )" or without:
  /// " one two three"  - additional whitespaces inside or around are ignored.
  static List<String> imapListToDartList(String string) {
    string = string.trim();
    Match match = new RegExp('^\\(? *([^()\r\n]*?) *\\)?\$').firstMatch(
        string);
    if (match == null) {
      throw new ArgumentError("The string given is not a vaild imap list.");
    }
    return match.group(1).split(" ")
      ..removeWhere((string) {
        return string.isEmpty;
      });
  }

  /// Turns a List (One Two Three Four) into a Map {One: Two, Three: Four}
  ///
  /// Throws an [ArgumentError] if the string is not a valid list. See
  /// [imapListToDartList] for examples of valid lists.
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