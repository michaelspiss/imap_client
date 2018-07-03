import 'package:ImapClient/imap_client.dart';
import 'package:test/test.dart';

void main() {
  group('stringToList tests', () {
    test('Handles valid list', () {
      expect(ImapAnalyzer.stringToList("(one two three)"),
          ["one", "two", "three"]);
    });
    test('Handles valid list with spaces around', () {
      expect(ImapAnalyzer.stringToList(" (one two three) "),
          ["one", "two", "three"]);
    });
    test('Handles list with too many spaces between arguments', () {
      expect(ImapAnalyzer.stringToList("(one  two    three)"),
          ["one", "two", "three"]);
    });
    test("Handles list with spaces on the brackets' inside", () {
      expect(ImapAnalyzer.stringToList("( one two three )"),
          ["one", "two", "three"]);
    });
  });
}
