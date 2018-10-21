import 'package:imap_client/imap_client.dart';
import 'package:test/test.dart';
import 'dart:async';

void main() {
  StreamController<List<int>> _controller;
  ImapBuffer _buffer;

  setUp(() {
    _controller = new StreamController<List<int>>.broadcast();
    _buffer = ImapBuffer.bindToStream(_controller.stream);
  });

  group('readLine tests', () {
    test('Can read one line', () async {
      var list = _getCharCodeListFromString("some line\nsome other line\n");
      _controller.add(list);
      expect(await _buffer.readLine(), "some line");
    });
    test('Can read two lines', () async {
      var list = _getCharCodeListFromString("some line\nsome other line\n");
      _controller.add(list);
      expect(await _buffer.readLine(), "some line");
      expect(await _buffer.readLine(), "some other line");
    });
    test('Removes whitespaces at the beginning', () async {
      var list = _getCharCodeListFromString(" \r\tsome line\n");
      _controller.add(list);
      expect(await _buffer.readLine(), "some line");
    });
    test('Not-releasing the buffer does not cause weird behavior', () async {
      var list = _getCharCodeListFromString("12345\n67890\n");
      _controller.add(list);
      await _buffer.readLine(autoReleaseBuffer: false);
      expect(await _buffer.readLine(autoReleaseBuffer: false), "67890");
    });
  });

  group("readQuotedString tests", () {
    test('Can read single quoted string', () async {
      var list =
          _getCharCodeListFromString("\"some string\" \"some other string\"");
      _controller.add(list);
      expect((await _buffer.readQuotedString()).value, "some string");
    });
    test('Has correct type', () async {
      var list =
          _getCharCodeListFromString("\"some string\" \"some other string\"");
      _controller.add(list);
      expect((await _buffer.readQuotedString()).type, ImapWordType.string);
    });
    test('Can read two quoted strings', () async {
      var list =
          _getCharCodeListFromString("\"some string\" \"some other string\"");
      _controller.add(list);
      expect((await _buffer.readQuotedString()).value, "some string");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readQuotedString()).value, "some other string");
    });
    test("Throws InvalidFormatException if string doesn't start with quotes",
        () async {
      var list = _getCharCodeListFromString("missing quotes\"");
      _controller.add(list);
      expect(await () async => await _buffer.readQuotedString(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("readLiteral tests", () {
    test('Can read single char', () async {
      var list = _getCharCodeListFromString("{1}\na");
      _controller.add(list);
      expect((await _buffer.readLiteral()).value, "a");
    });
    test('Has correct type', () async {
      var list = _getCharCodeListFromString("{1}\na");
      _controller.add(list);
      expect((await _buffer.readLiteral()).type, ImapWordType.string);
    });
    test('Can read multiple chars including linebreaks and specials', () async {
      var list = _getCharCodeListFromString("{19}\n12@4\n6\r\t9NIL{[]}()0");
      _controller.add(list);
      expect((await _buffer.readLiteral()).value, "12@4\n6\r\t9NIL{[]}()0");
    });
    test('Can read multiple literals', () async {
      var list = _getCharCodeListFromString("{1}\n1 {1}\n2");
      _controller.add(list);
      expect((await _buffer.readLiteral()).value, "1");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readLiteral()).value, "2");
    });
    test(
        'Throws InvalidFormatException if it does not start with curly bracket',
        () async {
      var list = _getCharCodeListFromString("missing bracket");
      _controller.add(list);
      expect(await () async => await _buffer.readLiteral(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("readFlag tests", () {
    test('Can read single flag', () async {
      var list = _getCharCodeListFromString("\\Flag ");
      _controller.add(list);
      expect((await _buffer.readFlag()).value, "Flag");
    });
    test('Has correct type', () async {
      var list = _getCharCodeListFromString("\\Flag ");
      _controller.add(list);
      expect((await _buffer.readFlag()).type, ImapWordType.flag);
    });
    test('Does not include non atom chars', () async {
      var list = _getCharCodeListFromString("\\Flag] ");
      _controller.add(list);
      expect((await _buffer.readFlag()).value, "Flag");
    });
    test('Can read multiple flags', () async {
      var list = _getCharCodeListFromString("\\FlagOne \\FlagTwo ");
      _controller.add(list);
      expect((await _buffer.readFlag()).value, "FlagOne");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readFlag()).value, "FlagTwo");
    });
    test('Throws InvalidFormatException if it does not start with backslash',
        () async {
      var list = _getCharCodeListFromString("missing backslash");
      _controller.add(list);
      expect(await () async => await _buffer.readFlag(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("readAtom tests", () {
    test('Can read single char', () async {
      var list = _getCharCodeListFromString("a ");
      _controller.add(list);
      expect((await _buffer.readAtom()).value, "a");
    });
    test('Has correct type', () async {
      var list = _getCharCodeListFromString("a ");
      _controller.add(list);
      expect((await _buffer.readAtom()).type, ImapWordType.atom);
    });
    test('Can read multiple atoms', () async {
      var list = _getCharCodeListFromString("A0001 OK ");
      _controller.add(list);
      expect((await _buffer.readAtom()).value, "A0001");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readAtom()).value, "OK");
    });
    test('Throws InvalidFormatException if it starts with illegal character',
        () async {
      var list = _getCharCodeListFromString("\\");
      _controller.add(list);
      expect(await () async => await _buffer.readAtom(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("skipWhitespaces tests", () {
    test("skipWhitespaces skips all whitespaces", () async {
      var list = _getCharCodeListFromString(" \r\tOK ");
      _controller.add(list);
      await _buffer.skipWhitespaces();
      expect((await _buffer.readAtom()).value, "OK");
    });
  });

  group("readWord tests", () {
    test("readWord skips whitespaces at beginning", () async {
      var list = _getCharCodeListFromString(" \r\tOK ");
      _controller.add(list);
      expect((await _buffer.readWord()).value, "OK");
    });
    test("readWord recognizes special char", () async {
      var list = _getCharCodeListFromString("* ");
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.tokenAsterisk);
    });
    test("readWord recognizes special char without following whitespace",
        () async {
      var list = _getCharCodeListFromString("*A ");
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.tokenAsterisk);
    });
    test("readWord recognizes quoted string", () async {
      var list = _getCharCodeListFromString("\"some string\"");
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.string);
    });
    test("readWord recognizes literal", () async {
      var list = _getCharCodeListFromString("{1}\n1");
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.string);
    });
    test("readWord recognizes flag", () async {
      var list = _getCharCodeListFromString("\\Flag ");
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.flag);
    });
    test("readWord recognizes atom", () async {
      var list = _getCharCodeListFromString("OK ");
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.atom);
    });
    test("readWord recognizes multiple words after another", () async {
      var list = _getCharCodeListFromString("\"some string\" {1}\n1 OK ");
      _controller.add(list);
      expect((await _buffer.readWord()).value, "some string");
      expect((await _buffer.readWord()).value, "1");
      expect((await _buffer.readWord()).value, "OK");
    });
  });
}

List<int> _getCharCodeListFromString(String input) {
  List<int> output = <int>[];
  for (int i = 0; i < input.length; i++) {
    output.add(input.codeUnitAt(i));
  }
  return output;
}
