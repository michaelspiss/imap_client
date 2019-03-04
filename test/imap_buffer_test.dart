import 'package:imap_client/imap_client.dart';
import 'package:test/test.dart';
import 'dart:async';

void main() {
  StreamController<List<int>> _controller;
  ImapBuffer _buffer;

  setUp(() {
    _controller = new StreamController<List<int>>.broadcast();
    _buffer = ImapBuffer();
    _controller.stream.listen((data) {
      _buffer.addAll(data);
    });
  });

  group('readLine tests', () {
    test('Can read one line', () async {
      var list = "some line\nsome other line\n".codeUnits;
      _controller.add(list);
      expect(await _buffer.readLine(), "some line");
    });
    test('Can read two lines', () async {
      var list = "some line\nsome other line\n".codeUnits;
      _controller.add(list);
      expect(await _buffer.readLine(), "some line");
      expect(await _buffer.readLine(), "some other line");
    });
    test('Removes whitespaces at the beginning', () async {
      var list = " \r\tsome line\n".codeUnits;
      _controller.add(list);
      expect(await _buffer.readLine(), "some line");
    });
    test('Not-releasing the buffer does not cause weird behavior', () async {
      var list = "12345\n67890\n".codeUnits;
      _controller.add(list);
      await _buffer.readLine(autoReleaseBuffer: false);
      expect(await _buffer.readLine(autoReleaseBuffer: false), "67890");
    });
    test('Can read empty line', () async {
      var list = "\n\n".codeUnits;
      _controller.add(list);
      expect(await _buffer.readLine(), "");
      expect(await _buffer.readLine(), "");
    });
  });

  group('skipLine tests', () {
    test('reads exactly one line', () async {
      var list = "some line\nsome other line\n".codeUnits;
      _controller.add(list);
      await _buffer.skipLine();
      expect(await _buffer.readLine(), "some other line");
    });
    test('Not-releasing the buffer does not cause weird behavior', () async {
      var list = "some line\nsome other line\n".codeUnits;
      _controller.add(list);
      await _buffer.skipLine(autoReleaseBuffer: false);
      expect(await _buffer.readLine(), "some other line");
    });
  });

  group("readQuotedString tests", () {
    test('Can read single quoted string', () async {
      var list = "\"some string\" \"some other string\"".codeUnits;
      _controller.add(list);
      expect((await _buffer.readQuotedString()).value, "some string");
    });
    test('Has correct type', () async {
      var list = "\"some string\" \"some other string\"".codeUnits;
      _controller.add(list);
      expect((await _buffer.readQuotedString()).type, ImapWordType.string);
    });
    test('Can read two quoted strings', () async {
      var list = "\"some string\" \"some other string\"".codeUnits;
      _controller.add(list);
      expect((await _buffer.readQuotedString()).value, "some string");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readQuotedString()).value, "some other string");
    });
    test("Throws InvalidFormatException if string doesn't start with quotes",
        () async {
      var list = "missing quotes\"".codeUnits;
      _controller.add(list);
      expect(await () async => await _buffer.readQuotedString(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("readLiteral tests", () {
    test('Can read single char', () async {
      var list = "{1}\na".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLiteral()).value, "a");
    });
    test('Has correct type', () async {
      var list = "{1}\na".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLiteral()).type, ImapWordType.string);
    });
    test('Can read multiple chars including linebreaks and specials', () async {
      var list = "{19}\n12@4\n6\r\t9NIL{[]}()0".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLiteral()).value, "12@4\n6\r\t9NIL{[]}()0");
    });
    test('Can read multiple literals', () async {
      var list = "{1}\n1 {1}\n2".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLiteral()).value, "1");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readLiteral()).value, "2");
    });
    test(
        'Throws InvalidFormatException if it does not start with curly bracket',
        () async {
      var list = "missing bracket".codeUnits;
      _controller.add(list);
      expect(await () async => await _buffer.readLiteral(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("readFlag tests", () {
    test('Can read single flag', () async {
      var list = "\\Flag ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readFlag()).value, "Flag");
    });
    test('Has correct type', () async {
      var list = "\\Flag ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readFlag()).type, ImapWordType.flag);
    });
    test('Does not include non atom chars', () async {
      var list = "\\Flag] ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readFlag()).value, "Flag");
    });
    test('Can read multiple flags', () async {
      var list = "\\FlagOne \\FlagTwo ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readFlag()).value, "FlagOne");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readFlag()).value, "FlagTwo");
    });
    test('Throws InvalidFormatException if it does not start with backslash',
        () async {
      var list = "missing backslash".codeUnits;
      _controller.add(list);
      expect(await () async => await _buffer.readFlag(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("readAtom tests", () {
    test('Can read single char', () async {
      var list = "a ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readAtom()).value, "a");
    });
    test('Has correct type', () async {
      var list = "a ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readAtom()).type, ImapWordType.atom);
    });
    test('Can read multiple atoms', () async {
      var list = "A0001 OK ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readAtom()).value, "A0001");
      await _buffer.skipWhitespaces();
      expect((await _buffer.readAtom()).value, "OK");
    });
    test('Throws InvalidFormatException if it starts with illegal character',
        () async {
      var list = "\\".codeUnits;
      _controller.add(list);
      expect(await () async => await _buffer.readAtom(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("skipWhitespaces tests", () {
    test("skipWhitespaces skips all whitespaces", () async {
      var list = " \r\tOK ".codeUnits;
      _controller.add(list);
      await _buffer.skipWhitespaces();
      expect((await _buffer.readAtom()).value, "OK");
    });
  });

  group("readWord tests", () {
    test("readWord skips whitespaces at beginning", () async {
      var list = " \r\tOK ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).value, "OK");
    });
    test("readWord recognizes special char", () async {
      var list = "* ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.tokenAsterisk);
    });
    test("readWord recognizes special char without following whitespace",
        () async {
      var list = "*A ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.tokenAsterisk);
    });
    test("readWord recognizes quoted string", () async {
      var list = "\"some string\"".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.string);
    });
    test("readWord recognizes literal", () async {
      var list = "{1}\n1".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.string);
    });
    test("readWord recognizes flag", () async {
      var list = "\\Flag ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.flag);
    });
    test("readWord recognizes atom", () async {
      var list = "OK ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).type, ImapWordType.atom);
    });
    test("readWord recognizes multiple words after another", () async {
      var list = "\"some string\" {1}\n1 OK ".codeUnits;
      _controller.add(list);
      expect((await _buffer.readWord()).value, "some string");
      expect((await _buffer.readWord()).value, "1");
      expect((await _buffer.readWord()).value, "OK");
    });
    test("readWord throws exception if word is not of expected type", () async {
      var list = "atom\n";
      _controller.add(list.codeUnits);
      expect(
          await () async => await _buffer.readWord(expected: ImapWordType.eol),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });

  group("unread tests", () {
    test("unread can unread single newline", () async {
      var list = "some string\nsome other string\n".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLine()), "some string");
      _buffer.unread("\n");
      expect((await _buffer.readLine()), "");
      expect((await _buffer.readLine()), "some other string");
    });
    test("unread can unread line", () async {
      var list = "some string\nsome other string\n".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLine()), "some string");
      _buffer.unread("unread\n");
      expect((await _buffer.readLine()), "unread");
      expect((await _buffer.readLine()), "some other string");
    });
    test("unread can unread nothing", () async {
      var list = "some string\nsome other string\n".codeUnits;
      _controller.add(list);
      expect((await _buffer.readLine()), "some string");
      _buffer.unread("");
      expect((await _buffer.readLine()), "some other string");
    });
  });

  group("readInteger tests", () {
    test("readInteger reads single integer", () async {
      var list = "1234567890\n";
      _controller.add(list.codeUnits);
      expect(await _buffer.readInteger(), 1234567890);
    });
    test("readInteger reads integer with appended zeros", () async {
      var list = "00001234567890\n";
      _controller.add(list.codeUnits);
      expect(await _buffer.readInteger(), 1234567890);
    });
    test("readInteger reads two integers", () async {
      var list = "1234567890 123\n";
      _controller.add(list.codeUnits);
      expect(await _buffer.readInteger(), 1234567890);
      expect(await _buffer.readInteger(), 123);
    });
    test("readInteger reads negative integers", () async {
      var list = "-1234567890\n";
      _controller.add(list.codeUnits);
      expect(await _buffer.readInteger(), -1234567890);
    });
    test("readInteger throws exception if read value is not an int", () async {
      var list = "notAnumber\n";
      _controller.add(list.codeUnits);
      expect(await () async => await _buffer.readInteger(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
    test("readInteger throws exception if number has invalid char", () async {
      var list = "123A456\n";
      _controller.add(list.codeUnits);
      expect(await () async => await _buffer.readInteger(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
    test("readInteger throws exception if number is not an int", () async {
      var list = "1.00\n";
      _controller.add(list.codeUnits);
      expect(await () async => await _buffer.readInteger(),
          throwsA(new TypeMatcher<InvalidFormatException>()));
    });
  });
}
