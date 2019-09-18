import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:imap_client/imap_client.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class FakeSocket extends Fake implements Socket {
  StreamController<Uint8List> input;
  String nextResponse;

  FakeSocket(this.input);

  @override
  StreamSubscription<Uint8List> listen(void onData(Uint8List event),
      {Function onError, void onDone(), bool cancelOnError}) {
    return input.stream.listen(onData);
  }

  @override
  void write(Object object) async {
    if (object is String) {
      if (object.startsWith("A2")) {
        input.add(Uint8List.fromList("A2 OK\r\n".codeUnits));
      } else if (object.contains("FETCH")) {
        input.add(Uint8List.fromList("$nextResponse\r\n".codeUnits));
      }
    }
  }
}

void main() {
  StreamController<Uint8List> server = new StreamController.broadcast();
  FakeSocket socket = new FakeSocket(server);
  ImapEngine engine;
  ImapFolder _folder;

  setUp(() {
    server.stream.drain();
    engine = new ImapEngine(socket);
    _folder = new ImapFolder(engine, "TestFolder");
    server.add(Uint8List.fromList(
        "* OK [CAPABILITY Imap4rev1]\r\nA1 OK\r\n".codeUnits));
  });

  /*
    Test cases are based on the following examples:
    
      http://sgerwk.altervista.org/imapbodystructure.html

    These just check to make sure no exceptions are thrown, but could be expanded to verify expected _result
    
  */

  test('single-part email', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE("TEXT" "PLAIN" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 1315 42 NIL NIL NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('text + html', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 2234 63 NIL NIL NIL NIL)("TEXT" "HTML" ("CHARSET" "iso-8859-1") NIL NIL "QUOTED-PRINTABLE" 2987 52 NIL NIL NIL NIL) "ALTERNATIVE" ("BOUNDARY" "d3438gr7324") NIL NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('mail with images', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("TEXT" "HTML" ("CHARSET" "US-ASCII") NIL NIL "7BIT" 119 2 NIL ("INLINE" NIL) NIL)("IMAGE" "JPEG" ("NAME" "4356415.jpg") "<0__=rhksjt>" NIL "BASE64" 143804 NIL ("INLINE" ("FILENAME" "4356415.jpg")) NIL) "RELATED" ("BOUNDARY" "0__=5tgd3d") ("INLINE" NIL) NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('text + html with images', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "ISO-8859-1" "FORMAT" "flowed") NIL NIL "QUOTED-PRINTABLE" 2815 73 NIL NIL NIL NIL)(("TEXT" "HTML" ("CHARSET" "ISO-8859-1") NIL NIL "QUOTED-PRINTABLE" 4171 66 NIL NIL NIL NIL)("IMAGE" "JPEG" ("NAME" "image.jpg") "<3245dsf7435>" NIL "BASE64" 189906 NIL NIL NIL NIL)("IMAGE" "GIF" ("NAME" "other.gif") "<32f6324f>" NIL "BASE64" 1090 NIL NIL NIL NIL) "RELATED" ("BOUNDARY" "--=sdgqgt") NIL NIL NIL) "ALTERNATIVE" ("BOUNDARY" "--=u5sfrj") NIL NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('mail with images', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "ISO-8859-1") NIL NIL "QUOTED-PRINTABLE" 471 28 NIL NIL NIL)("TEXT" "HTML" ("CHARSET" "ISO-8859-1") NIL NIL "QUOTED-PRINTABLE" 1417 36 NIL ("INLINE" NIL) NIL) "ALTERNATIVE" ("BOUNDARY" "1__=hqjksdm") NIL NIL)("IMAGE" "GIF" ("NAME" "image.gif") "<1__=cxdf2f>" NIL "BASE64" 50294 NIL ("INLINE" ("FILENAME" "image.gif")) NIL) "RELATED" ("BOUNDARY" "0__=hqjksdm") NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('mail with attachment', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("TEXT" "HTML" ("CHARSET" "ISO-8859-1") NIL NIL "QUOTED-PRINTABLE" 4692 69 NIL NIL NIL NIL)("APPLICATION" "PDF" ("NAME" "pages.pdf") NIL NIL "BASE64" 38838 NIL ("attachment" ("FILENAME" "pages.pdf")) NIL NIL) "MIXED" ("BOUNDARY" "----=6fgshr") NIL NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('alternative and attachment', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE ((("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 403 6 NIL NIL NIL NIL)("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 421 6 NIL NIL NIL NIL) "ALTERNATIVE" ("BOUNDARY" "----=fghgf3") NIL NIL NIL)("APPLICATION" "MSWORD" ("NAME" "letter.doc") NIL NIL "BASE64" 110000 NIL ("attachment" ("FILENAME" "letter.doc" "SIZE" "80384")) NIL NIL) "MIXED" ("BOUNDARY" "----=y34fgl") NIL NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('all together', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (((("TEXT" "PLAIN" ("CHARSET" "ISO-8859-1") NIL NIL "QUOTED-PRINTABLE" 833 30 NIL NIL NIL)("TEXT" "HTML" ("CHARSET" "ISO-8859-1") NIL NIL "QUOTED-PRINTABLE" 3412 62 NIL ("INLINE" NIL) NIL) "ALTERNATIVE" ("BOUNDARY" "2__=fgrths") NIL NIL)("IMAGE" "GIF" ("NAME" "485039.gif") "<2__=lgkfjr>" NIL "BASE64" 64 NIL ("INLINE" ("FILENAME" "485039.gif")) NIL) "RELATED" ("BOUNDARY" "1__=fgrths") NIL NIL)("APPLICATION" "PDF" ("NAME" "title.pdf") "<1__=lgkfjr>" NIL "BASE64" 333980 NIL ("ATTACHMENT" ("FILENAME" "title.pdf")) NIL) "MIXED" ("BOUNDARY" "0__=fgrths") NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('single-element lists', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("TEXT" "HTML" NIL NIL NIL "7BIT" 151 0 NIL NIL NIL) "MIXED" ("BOUNDARY" "----=rfsewr") NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  //--- other test variations

  test('text + html with "inline" images', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("text" "plain" ("charset" "utf-8") NIL NIL "7bit" 160 10 NIL NIL NIL NIL)(("text" "html" ("charset" "utf-8") NIL NIL "7bit" 452 15 NIL NIL NIL NIL)("image" "png" ("name" "kmdhkbcgedflagom.png") "<part1.949092FE.5A7457AA@librem.one>" NIL "base64" 29594 NIL ("inline" ("filename" "kmdhkbcgedflagom.png")) NIL NIL) "related" ("boundary" "------------4F31590A57C94ECEEA4EE609") NIL NIL NIL) "alternative" ("boundary" "------------E4A51DD138E4E2F27347C5BC") NIL ("en-US") NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });

  test('"inline" pgp signature', () async {
    socket.nextResponse =
        """* 1 FETCH (BODYSTRUCTURE (("application" "pgp-encrypted" NIL NIL NIL "7bit" 12 NIL NIL NIL NIL)("application" "octet-stream" ("name" "encrypted.asc") NIL NIL "7bit" 933 NIL ("inline" ("filename" "encrypted.asc")) NIL NIL) "encrypted" ("boundary" "5ceef4c9_74b0dc51_1a6" "protocol" "application/pgp-encrypted") NIL NIL NIL))\r\nA1 OK\r\n""";
    await _folder.fetch([], messageIds: [1]);
  });
}
