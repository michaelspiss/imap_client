import 'package:ImapClient/imap_client.dart';
import 'package:test/test.dart';

void main() {
  group('imapListToDartList tests', () {
    test('Handles valid list', () {
      expect(ImapConverter.imapListToDartList("(one two three)"),
          ["one", "two", "three"]);
    });
    test('Handles valid list with spaces around', () {
      expect(ImapConverter.imapListToDartList(" (one two three) "),
          ["one", "two", "three"]);
    });
    test('Handles list with too many spaces between arguments', () {
      expect(ImapConverter.imapListToDartList("(one  two    three)"),
          ["one", "two", "three"]);
    });
    test("Handles list with spaces on the brackets' inside", () {
      expect(ImapConverter.imapListToDartList("( one two three )"),
          ["one", "two", "three"]);
    });
    test("Handles list without brackets", () {
      expect(ImapConverter.imapListToDartList("one two three"),
          ["one", "two", "three"]);
    });
    test("Handles list without brackets and spaces around", () {
      expect(ImapConverter.imapListToDartList(" one two three "),
          ["one", "two", "three"]);
    });
  });
}
