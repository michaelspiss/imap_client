import 'package:ImapClient/imap_client.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'dart:async';

int port = 6153;
String host = "127.0.0.1";

class TestServer {
  ServerSocket socket;
  Socket client;
  Future hasConnection;
  Completer _completer;
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
        if(sendOKGreeting) {
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

  group('Server greetings', ()
  {
    setUp(() {
      server.sendOKGreeting = false;
    });

    test('Client connect is complete when server sends greeting', () {
      bool greetingSent = false;
      client.connect(host, port, false).then((_) {
        expect(greetingSent, isTrue);
      });
      server.hasConnection.then((_) {
        Future.delayed(Duration(seconds: 1), () {
          greetingSent = true;
          server.client.write("* OK\r\n");
        });
      });
    });
    test('Client sets state to connected after OK', () {
      client.connect(host, port, false).then((_) {
        expect(client.connectionState, ImapClient.stateConnected);
      });
      server.hasConnection.then((_) {
        server.client.write("* OK\r\n");
      });
    });
    test('Client sets state to authenticated after PREAUTH', () {
      client.connect(host, port, false).then((_) {
        expect(client.connectionState, ImapClient.stateAuthenticated);
      });
      server.hasConnection.then((_) {
        server.client.write("* PREAUTH\r\n");
      });
    });
    test('Client sets state to closed after BYE and disconnect', () {
      expect(client.connect(host, port, false).then((_) {
        expect(client.connectionState, ImapClient.stateClosed);
      }), completes);
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
}
