import 'package:imap_client/imap_client.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'dart:async';

int port = 36153;
String host = "127.0.0.1";

class TestServer {
  ServerSocket socket;
  Socket client;
  Future hasConnection;
  Completer _completer;

  /// Set to false to send custom greeting
  bool sendOKGreeting = true;

  TestServer() {
    _completer = new Completer();
    hasConnection = _completer.future;
    ServerSocket.bind(host, port).then((socket) {
      this.socket = socket;
      this.socket.listen((client) {
        this.client = client;
        _completer.complete();
        _completer = new Completer();
        hasConnection = _completer.future;
        if (sendOKGreeting) {
          client.write("* OK [CAPABILITY IMAP4rev1 IDLE AUTH=PLAIN]\r\n");
        }
        sendOKGreeting = true;
      });
    });
  }
}

TestServer server = new TestServer();

void main() {
  ImapClient client;

  setUp(() {
    client = new ImapClient();
  });

  group('Server greetings', () {
    setUp(() {
      server.sendOKGreeting = false;
    });

    test('Client connect is complete when server sends greeting', () {
      bool greetingSent = false;
      expect(
          client.connect(host, port, false).then((_) {
            expect(greetingSent, isTrue);
          }),
          completes);
      server.hasConnection.then((_) {
        new Future.delayed(new Duration(seconds: 1), () {
          greetingSent = true;
          server.client.write("* OK\r\n");
        });
      });
    });
    test('Client sets state to connected after OK', () {
      expect(
          client.connect(host, port, false).then((_) {
            expect(client.connectionState, ImapClient.stateConnected);
          }),
          completes);
      server.hasConnection.then((_) {
        server.client.write("* OK\r\n");
      });
    });
    test('Client sets state to authenticated after PREAUTH', () {
      expect(
          client.connect(host, port, false).then((_) {
            expect(client.connectionState, ImapClient.stateAuthenticated);
          }),
          completes);
      server.hasConnection.then((_) {
        server.client.write("* PREAUTH\r\n");
      });
    });
    test('Client sets state to closed after BYE and disconnect', () {
      expect(
          client.connect(host, port, false).then((_) {
            expect(client.connectionState, ImapClient.stateClosed);
          }),
          completes);
      server.hasConnection.then((_) {
        server.client.write("* BYE\r\n");
        server.client.close();
      });
    });
  });

  group('Capability tests', () {
    test("Capabilites are recorded when sent with response", () async {
      await client.connect(host, port, false);
      expect(client.serverCapabilities, ["IMAP4rev1", "IDLE"]);
    });
    test("Auth methods are recorded when sent with response", () async {
      await client.connect(host, port, false);
      expect(client.serverSupportedAuthMethods, ["PLAIN"]);
    });
    test("Client does update capabilities automatically on command", () async {
      await client.connect(host, port, false);
      client.capability().then((_) {
        expect(client.serverCapabilities, ["IMAP4rev1", "something"]);
      });
      server.client.write("* CAPABILITY IMAP4rev1 something\r\nA0 OK\r\n");
    });
    test("Client does update authentication methods on command", () async {
      await client.connect(host, port, false);
      client.capability().then((_) {
        expect(client.serverSupportedAuthMethods, []);
      });
      server.client.write("* CAPABILITY IMAP4rev1 something\r\nA0 OK\r\n");
    });
  });

  group('State detection by helper functions', () {
    test('"connected" after OK greeting', () async {
      await client.connect(host, port, false);
      expect(client.isConnected(), isTrue);
    });
    test('"authenticated" after PREAUTH greeting', () {
      server.sendOKGreeting = false;
      expect(
          client.connect(host, port, false).then((_) {
            expect(client.isAuthenticated(), isTrue);
          }),
          completes);
      server.hasConnection.then((_) {
        server.client.write("* PREAUTH\r\n");
      });
    });
    test('"selected" after mailbox selection', () async {
      await client.connect(host, port, false);
      expect(
          client.select("INBOX").then((_) {
            expect(client.isSelected(), isTrue);
          }),
          completes);
      server.client.listen((_) {
        server.client.write("A0 OK\r\n");
      });
    });
    test('"idle" after idle command was accepted', () async {
      await client.connect(host, port, false);
      client.idle().then((_) {
        expect(client.isIdle(), isTrue);
      });
      server.client.listen((_) {
        server.client.write("+ idling\r\n");
      });
    });
  });

  group('Commands having side effects do them', () {
    //
    // capability has its own group, so it's being skipped here
    //
    test('logout() sets connection state to closed', () async {
      await client.connect(host, port, false);
      expect(
          client.logout().then((_) {
            expect(client.connectionState == ImapClient.stateClosed, isTrue);
          }),
          completes);
      server.client.listen((_) {
        server.client.write("A0 OK\r\n");
      });
    });
    test('authenticate sets state to authenticated after successful login',
        () async {
      await client.connect(host, port, false);
      expect(
          client.authenticate("username", "password").then((_) {
            expect(client.isAuthenticated(), isTrue);
          }),
          completes);
      int i = 0;
      server.client.listen((_) {
        server.client.write(["+\r\n", "A0 OK"].elementAt(i++));
      });
    });
    test('authenticate resets capabilities if no new were given', () async {
      await client.connect(host, port, false);
      expect(
          client.authenticate("username", "password").then((_) {
            expect(client.serverCapabilities, []);
          }),
          completes);
      int i = 0;
      server.client.listen((_) {
        server.client.write(["+\r\n", "A0 OK\r\n"].elementAt(i++));
      });
    });
    test('login sets state to authenticated after successful login', () async {
      await client.connect(host, port, false);
      expect(
          client.login("username", "password").then((_) {
            expect(client.isAuthenticated(), isTrue);
          }),
          completes);
      server.client.listen((_) {
        server.client.write("A0 OK\r\n");
      });
    });
    test('login resets capabilities if no new were given', () async {
      await client.connect(host, port, false);
      expect(
          client.login("username", "password").then((_) {
            expect(client.serverCapabilities, []);
          }),
          completes);
      server.client.listen((_) {
        server.client.write("A0 OK\r\n");
      });
    });
    test('select sets read-only flag if given', () async {
      await client.connect(host, port, false);
      expect(
          client.select("INBOX").then((_) {
            expect(client.mailboxIsReadWrite, isFalse);
          }),
          completes);
      server.client.listen((_) {
        server.client.write("A0 OK [READ-ONLY]\r\n");
      });
    });
    test('select sets read-write flag if nothing was given', () async {
      await client.connect(host, port, false);
      expect(
          client.select("INBOX").then((_) {
            expect(client.mailboxIsReadWrite, isTrue);
          }),
          completes);
      server.client.listen((_) {
        server.client.write("A0 OK\r\n");
      });
    });
    test('login() throws error if disabled by server', () async {
      server.sendOKGreeting = false;
      expect(
          client.connect(host, port, false).then((_) {
            expect(() => client.login("", ""), throwsUnsupportedError);
          }),
          completes);
      server.hasConnection.then((_) {
        server.client.write("* OK [CAPABILITY IMAP4rev1 LOGINDISABLED]\r\n");
      });
    });
  });

  group('idle() tests', () {
    test('idle() throws error if unsupported by server', () async {
      server.sendOKGreeting = false;
      expect(
          client.connect(host, port, false).then((_) {
            expect(() => client.idle(), throwsUnsupportedError);
          }),
          completes);
      server.hasConnection.then((_) {
        server.client.write("* OK [CAPABILITY IMAP4rev1]\r\n");
      });
    });
  });

  /*
   *
   * ANALYZER
   * TESTS
   *
   */

  group("Command completion tests", () {
    test("Completion handler added first will handle first request (fifo)",
        () async {
      bool handledByFirst = false;
      Completer done = new Completer();
      await client.connect(host, port, false);
      client.sendCommand("", (_) {
        handledByFirst = true;
        done.complete();
      });
      client.sendCommand("", (_) {
        handledByFirst = false;
        done.complete();
      });
      server.client.write("+\r\n");
      expect(done.future.then((_) {
        expect(handledByFirst, isTrue);
      }), completes);
    });
    test("Only one handler is called at a time", () async {
      await client.connect(host, port, false);
      void increaseCalls(_) => expectAsync0(() {}, count: 1);
      client.sendCommand("", increaseCalls);
      client.sendCommand("", increaseCalls);
      server.client.write("+\r\n");
    });
    test("Handler gets continuation info", () async {
      await client.connect(host, port, false);
      client.sendCommand("", (String info) {
        expect(info, "info");
      });
      server.client.write("+ info\r\n");
    });
    test("Continuation info is empty string if none given", () async {
      await client.connect(host, port, false);
      client.sendCommand("", (String info) {
        expect(info, "");
      });
      server.client.write("+\r\n");
    });
  });

  group("Command completion status tests", () {
    test('Response is marked as "OK" when status is "OK"', () async {
      await client.connect(host, port, false);
      expect(
          client.noop().then((res) {
            expect(res.isOK(), isTrue);
          }),
          completes);
      server.client.write("A0 OK\r\n");
    });
    test('Response is marked as "BAD" when status is "BAD"', () async {
      await client.connect(host, port, false);
      expect(
          client.noop().then((res) {
            expect(res.status, "BAD");
          }),
          completes);
      server.client.write("A0 BAD\r\n");
    });
    test('Response is marked as "NO" when status is "NO"', () async {
      await client.connect(host, port, false);
      expect(
          client.noop().then((res) {
            expect(res.status, "NO");
          }),
          completes);
      server.client.write("A0 NO\r\n");
    });
    test('Response status is always capitalized', () async {
      await client.connect(host, port, false);
      expect(
          client.noop().then((res) {
            expect(res.status, "BAD");
          }),
          completes);
      server.client.write("A0 bad\r\n");
    });
    test('Unknown response status is still transmitted', () async {
      await client.connect(host, port, false);
      expect(
          client.noop().then((res) {
            expect(res.status, "SOMETHING");
          }),
          completes);
      server.client.write("A0 SOMETHING\r\n");
    });
  });

  group("Literal handling tests", () {
    test("Literals can be info for command completion request", () async {
      await client.connect(host, port, false);
      expect(
          client.sendCommand("", (String info) {
            expect(info, "literal works");
            server.client.write("A0 OK\r\n");
          }),
          completes);
      server.client.write("+ {13}\r\nliteral works\r\n");
    });
    test("Literals can be fetch parts", () async {
      await client.connect(host, port, false);
      Completer done = new Completer();
      client.fetchHandler = (String mailboxName, int messageNumber,
          Map<String, String> attributes) {
        expect(attributes, {"ONE": "literal works"});
        done.complete();
      };
      server.client.write("* 17 FETCH (ONE {13}\r\nliteral works)\n* OK");
      expect(done.future, completes);
    });
    test("There can be multiple literals in a fetch response", () async {
      await client.connect(host, port, false);
      Completer done = new Completer();
      client.fetchHandler = (String mailboxName, int messageNumber,
          Map<String, String> attributes) {
        expect(attributes, {"ONE": "literal works", "TWO": "second works too"});
        done.complete();
      };
      server.client.write(
          "* 17 FETCH (ONE {13}\r\nliteral works TWO {16}\r\nsecond works too)\r\nA0 OK");
      expect(done.future, completes);
    });
  });
}
