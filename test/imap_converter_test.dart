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
    test("Handles list with spaces on the parenthesis' inside", () {
      expect(ImapConverter.imapListToDartList("( one two three  )"),
          ["one", "two", "three"]);
    });
    test("Handles list without parenthesis", () {
      expect(ImapConverter.imapListToDartList("one two three"),
          ["one", "two", "three"]);
    });
    test("Handles list without parenthesis and spaces around", () {
      expect(ImapConverter.imapListToDartList(" one two three "),
          ["one", "two", "three"]);
    });
    test("Throws an error if the argument is not a valid imap list", () {
      expect(() => ImapConverter.imapListToDartList(
          "not ( a valid ) list"), throwsArgumentError);
    });
  });

  group('imapListToDartMap tests', () {
    test('Handles valid list', () {
      expect(ImapConverter.imapListToDartMap("(one two three four)"),
          {"one": "two", "three": "four"});
    });
    test('Handles valid list with spaces around', () {
      expect(ImapConverter.imapListToDartMap(" (one two three four) "),
          {"one": "two", "three": "four"});
    });
    test('Handles list with too many spaces between arguments', () {
      expect(ImapConverter.imapListToDartMap("(one  two   three     four)"),
          {"one": "two", "three": "four"});
    });
    test("Handles list with spaces on the parenthesis' inside", () {
      expect(ImapConverter.imapListToDartMap("( one two three four  )"),
          {"one": "two", "three": "four"});
    });
    test("Handles list without parenthesis", () {
      expect(ImapConverter.imapListToDartMap("one two three four"),
          {"one": "two", "three": "four"});
    });
    test("Handles list without parenthesis and spaces around", () {
      expect(ImapConverter.imapListToDartMap(" one two three four  "),
          {"one": "two", "three": "four"});
    });
    test("Throws an error if the argument is not a valid imap list", () {
      expect(() => ImapConverter.imapListToDartMap(
          "not ( a valid ) list"), throwsArgumentError);
    });
  });

  group('dartListToImapList tests', () {
    test('Handles valid list', () {
      expect(ImapConverter.dartListToImapList(["one", "two", "three"]),
          "(one two three)");
    });
    test('Preserves spaces as item names', () {
      expect(ImapConverter.dartListToImapList(["one", " ", "three"]),
          "(one   three)");
    });
    test('Preserves empty item names', () {
      expect(ImapConverter.dartListToImapList(["one", "", "three"]),
          "(one  three)");
    });
  });

  group('dartMapToImapList tests', () {
    test('Handles valid map', () {
      expect(ImapConverter.dartMapToImapList({"one": "two", "three": "four"}),
          "(one two three four)");
    });
    test('Preserves spaces as item names', () {
      expect(ImapConverter.dartMapToImapList({"one": " ", "three": "four"}),
          "(one   three four)");
    });
    test('Preserves empty item names', () {
      expect(ImapConverter.dartMapToImapList({"one": "", "three": "four"}),
          "(one  three four)");
    });
  });
}
